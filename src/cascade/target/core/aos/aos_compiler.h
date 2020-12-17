// Copyright 2017-2019 VMware, Inc.
// SPDX-License-Identifier: BSD-2-Clause
//
// The BSD-2 license (the License) set forth below applies to all parts of the
// Cascade project.  You may not use this file except in compliance with the
// License.
//
// BSD-2 License
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS AS IS AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#ifndef CASCADE_SRC_TARGET_CORE_AOS_AOS_COMPILER_H
#define CASCADE_SRC_TARGET_CORE_AOS_AOS_COMPILER_H

#include <condition_variable>
#include <map>
#include <mutex>
#include <sstream>
#include <stdint.h>
#include <string>
#include <vector>
#include "common/indstream.h"
#include "target/compiler.h"
#include "target/core_compiler.h"
#include "target/core/aos/aos_logic.h"
#include "target/core/aos/rewrite.h"
#include "verilog/analyze/evaluate.h"
#include "verilog/analyze/module_info.h"
#include "verilog/ast/ast.h"

namespace cascade {

namespace aos {

template <typename T>
class AosCompiler : public CoreCompiler {
  public:
    AosCompiler();
    ~AosCompiler() override = default;

    // Core Compiler Interface:
    void stop_compile(Engine::Id id) override;

  protected:
    // Avalon Memory Mapped Compiler Interface
    //
    // This method should perform whatever target-specific logic is necessary
    // to return an instance of an AosLogic. 
    virtual AosLogic<T>* build(Interface* interface, ModuleDeclaration* md, size_t slot) = 0;
    // This method should perform whatever target-specific logic is necessary
    // to stop any previous compilations and compile text to a device. This
    // method is called in a context where it holds the global lock on this
    // compiler. Implementations for which this may take a long time should
    // release this lock, but reaquire it before returning.  This method should
    // return true of success, false on failure, say if stop_compile
    // interrupted a compilation.
    virtual bool compile(const std::string& text, std::mutex& lock) = 0;
    // This method should perform whatever target-specific logic is necessary
    // to stop the execution of any invocations of compile().
    virtual void stop_compile() = 0;

  private:
    // Compilation States:
    enum class State : uint8_t {
      FREE = 0,
      COMPILING,
      WAITING,
      STOPPED,
      CURRENT
    };
    // Slot Information:
    struct Slot {
      Engine::Id id;
      State state;
      std::string text;
    };

    // Program Management:
    std::mutex lock_;
    std::condition_variable cv_;
    std::vector<Slot> slots_;

    // Core Compiler Interface:
    AosLogic<T>* compile_logic(Engine::Id id, ModuleDeclaration* md, Interface* interface) override;

    // Slot Management Helpers:
    int get_free() const;
    void release(size_t slot);
    void stop_compile(Engine::Id id, bool force);
    void update();

    // Codegen Helpers:
    std::string get_text();
};

template <typename T>
inline AosCompiler<T>::AosCompiler() : CoreCompiler() {
  slots_.resize(32, {0, State::FREE, ""});
}

template <typename T>
inline void AosCompiler<T>::stop_compile(Engine::Id id) {
  std::lock_guard<std::mutex> lg(lock_);
  stop_compile(id, true);
}

template <typename T>
inline AosLogic<T>* AosCompiler<T>::compile_logic(Engine::Id id, ModuleDeclaration* md, Interface* interface) {
  std::unique_lock<std::mutex> lg(lock_);
  ModuleInfo info(md);

  // Check for unsupported language features
  auto unsupported = false;
  if (info.uses_mixed_triggers()) {
    get_compiler()->error("Aos backends do not currently support code with mixed triggers!");
    unsupported = true;
  } else if (!info.implied_latches().empty()) {
    get_compiler()->error("Aos backends do not currently support the use of implied latches!");
    unsupported = true;
  }
  if (unsupported) {
    delete md;
    return nullptr;
  }

  // Find a free slot 
  const auto slot = get_free();
  if (slot == -1) {
    get_compiler()->error("No remaining slots available on Aos device");
    delete md;
    return nullptr;
  }
  
  // Register inputs, state, and outputs. Invoke these methods
  // lexicographically to ensure a deterministic variable table ordering. The
  // final invocation of index_tasks is lexicographic by construction, as it's
  // based on a recursive descent of the AST.
  auto* al = build(interface, md, slot);
  if (al == nullptr) {
    get_compiler()->error("Aos build failed. Check that the Aos daemon is running.");
    return nullptr;
  }
  std::map<VId, const Identifier*> is;
  for (auto* i : info.inputs()) {
    is.insert(std::make_pair(to_vid(i), i));
  }
  for (const auto& i : is) {
    al->set_input(i.second, i.first);
  }
  std::map<VId, const Identifier*> ss, ssv;
  for (auto* s : info.stateful()) {
    if (info.is_volatile(s)) {
      ssv.insert(std::make_pair(to_vid(s), s));
    } else {
      ss.insert(std::make_pair(to_vid(s), s));
    }
  }
  for (const auto& s : ss) {
    al->set_state(false, s.second, s.first);
  }
  std::map<VId, const Identifier*> os;
  for (auto* o : info.outputs()) {
    os.insert(std::make_pair(to_vid(o), o));
  }
  for (const auto& o : os) {
    al->set_output(o.second, o.first);
  }
  al->index_tasks();
  // Check table and index sizes. If this program uses too much state, we won't
  // be able to uniquely name its elements using our current addressing scheme.
  const size_t nv_size = al->get_table()->size();
  if (nv_size >= 0x4000) {
    get_compiler()->error("Aos backends do not currently support more than 16,384 entries in variable table");
    delete al;
    return nullptr;
  }
  // Insert volatile variables at end of variable table
  for (const auto& s : ssv) {
    al->set_state(true, s.second, s.first);
  }
  const size_t table_size = al->get_table()->size();
  if (table_size != nv_size) {
    std::cout << "Found " << (table_size-nv_size) << " volatile variables" << std::endl;
  }

  // Downgrade any compilation slots to waiting slots, and stop any slots that
  // are working on this id.
  for (auto& s : slots_) {
    if (s.state == State::COMPILING) {
      s.state = State::WAITING;
    }
    if ((s.id == id) && (s.state == State::WAITING)) {
      s.state = State::STOPPED;
    }
  }
  // This slot is now the compile lead
  slots_[slot].id = id;
  slots_[slot].state = State::COMPILING;
  slots_[slot].text = Rewrite<T>().run(md, slot, al->get_table(), al->open_loop_clock(), nv_size);
  // Enter into compilation state machine. Control will exit from this loop
  // either when compilation succeeds or is aborted.
  while (true) {
    switch (slots_[slot].state) {
      case State::COMPILING:
        if (compile(get_text(), lock_)) {
          update();
        } else {
          //get_compiler()->error("Aos compile failed. Check compiler logs for errors.");
          //stop_compile(id, false);
        }
        break;
      case State::WAITING:
        cv_.wait(lg);
        break;
      case State::STOPPED:
        slots_[slot].state = State::FREE;
        delete al;
        return nullptr;
      case State::CURRENT:
        al->set_callback([this, slot]{release(slot);});
        return al;
      default:
        // Control should never reach here
        assert(false);
        break;
    }
  }
}

template <typename T>
inline int AosCompiler<T>::get_free() const {
  for (size_t i = 0, ie = slots_.size(); i < ie; ++i) {
    if (slots_[i].state == State::FREE) {
      return i;
    }
  }
  return -1;
}

template <typename T>
inline void AosCompiler<T>::release(size_t slot) {
  // Return this slot to the pool if necessary. This method is only invoked on
  // successfully compiled cores, which means we don't have to worry about
  // transfering compilation ownership or invoking stop_compile.
  std::lock_guard<std::mutex> lg(lock_);
  assert(slots_[slot].state == State::CURRENT);
  slots_[slot].state = State::FREE;
  cv_.notify_all();
}

template <typename T>
inline void AosCompiler<T>::stop_compile(Engine::Id id, bool force) {
  // Free any slot with this id which is in the compiling or waiting state.
  auto stopped = false;
  auto need_new_lead = false;
  for (auto& s : slots_) {
    if (s.id == id) {
      switch (s.state) {
        case State::COMPILING:
          need_new_lead = true;
          // fallthrough
        case State::WAITING:
          stopped = true;
          s.state = State::STOPPED;
          break;
        default:
          break;
      }
    }
  }
  // If nothing was stopped, we can return immediately.
  if (!stopped) {
    return;
  }
  // If we need a new compilation lead, find a waiting slot and promote it.
  if (need_new_lead) {
    for (auto rit = slots_.rbegin(), rend = slots_.rend(); rit != rend; ++rit) {
      if (rit->state == State::WAITING) {
        rit->state = State::COMPILING;
        break;
      }
    }
  }
  // Target-specific implementation of stop logic
  if (force) stop_compile();

  // Notify any waiting threads that the slot table has changed.
  cv_.notify_all();
}

template <typename T>
inline void AosCompiler<T>::update() {
  for (auto& s : slots_) {
    if ((s.state == State::COMPILING) || (s.state == State::WAITING)) {
      s.state = State::CURRENT;
    }     
  }
  cv_.notify_all();
}

template <typename T>
inline std::string AosCompiler<T>::get_text() {
  std::stringstream ss;
  indstream os(ss);

  // Generate code for modules
  std::map<MId, std::string> text;
  for (size_t i = 0, ie = slots_.size(); i < ie; ++i) {
    if (slots_[i].state != State::FREE) {
      text.insert(std::make_pair(i, slots_[i].text));
    }
  }

  // Module Declarations
  for (const auto& s : text) {
    os << s.second << std::endl;
    os << std::endl;
  }

  // Top-level Module
  os << "module program_logic(" << endl;
  os.tab();
  os << "input wire clk," << endl;
  os << "input wire reset," << endl;
  os << endl;
  os << "input wire         softreg_req_valid," << endl;
  os << "input wire         softreg_req_isWrite," << endl;
  os << "input wire[31:0]   softreg_req_addr," << endl;
  os << "input wire[63:0]   softreg_req_data," << endl;
  os << endl;
  os << "output wire        softreg_resp_valid," << endl;
  os << "output wire[63:0]  softreg_resp_data" << endl;
  os.untab();
  os << ");" << endl;
  os << endl;
  os.tab();
  
  os << "parameter app_num = 0;" << endl;
  os << endl;
  
  os << "// Register module signals" << endl;
  os << "reg        valid_in;" << endl;
  os << "reg        write_in;" << endl;
  os << "reg        read_in;" << endl;
  os << "reg[13:0]  addr_in;" << endl;
  os << "reg[63:0]  data_in;" << endl;
  os << endl;
  
  os << "wire       valid_out;" << endl;
  os << "wire[63:0] data_out;" << endl;
  os << "reg        valid_out_reg;" << endl;
  os << "reg[63:0]  data_out_reg;" << endl;
  os << endl;
  
  os << "always @(posedge clk) begin" << endl;
  os.tab();
  os << "if (reset) begin" << endl;
  os.tab();
  os << "valid_in <= 1'b0;" << endl;
  os << "write_in <= 1'b0;" << endl;
  os << "read_in <= 1'b0;" << endl;
  os << "addr_in <= 14'b0;" << endl;
  os << "data_in <= 64'b0;" << endl;
  os.untab();
  os << "end else begin" << endl;
  os.tab();
  os << "valid_in <= softreg_req_valid;" << endl;
  os << "write_in <= softreg_req_valid & softreg_req_isWrite;" << endl;
  os << "read_in <= softreg_req_valid & ~softreg_req_isWrite;" << endl;
  os << "addr_in <= softreg_req_addr[16:3];" << endl;
  os << "data_in <= softreg_req_data;" << endl;
  os.untab();
  os << "end" << endl;
  os << endl;
  
  os << "if (reset) begin" << endl;
  os.tab();
  os << "valid_out_reg <= 1'b0;" << endl;
  os << "data_out_reg <= 64'b0;" << endl;
  os.untab();
  os << "end else begin" << endl;
  os.tab();
  os << "valid_out_reg <= valid_out;" << endl;
  os << "data_out_reg <= data_out;" << endl;
  os.untab();
  os << "end" << endl;
  os.untab();
  os << "end" << endl;
  os << endl;
  os << "assign softreg_resp_valid = valid_out_reg;" << endl;
  os << "assign softreg_resp_data = data_out_reg;" << endl;
  os << endl;
  
  os << "// Module Instantiations:" << endl;
  os << "generate" << endl;
  for (const auto& s : text) {
    os << "if (app_num == " << s.first << ") begin" << endl;
    os.tab();
    os << "M" << s.first << " m (" << endl;
    os.tab();
    os << ".__clk(clk)," << endl;
    os << ".__in_read(write_in)," << endl;
    os << ".__in_vid(addr_in)," << endl;
    os << ".__in_data(data_in)," << endl;
    os << ".__in_valid(valid_in)," << endl;
    os << ".__out_data(data_out)," << endl;
    os << ".__out_valid(valid_out)" << endl;
    os.untab();
    os << ");" << endl;
    os.untab();
    os << "end" << endl;
  }
  os << "endgenerate" << endl;
  
  os.untab();
  os << "endmodule";

  return ss.str();
}

} // namespace aos

} // namespace cascade

#endif
