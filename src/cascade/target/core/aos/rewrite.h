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

#ifndef CASCADE_SRC_TARGET_CORE_AOS_REWRITE_H
#define CASCADE_SRC_TARGET_CORE_AOS_REWRITE_H

#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>
#include "target/core/aos/var_table.h"
#include "target/core/aos/machinify.h"
#include "target/core/aos/text_mangle.h"
#include "verilog/analyze/module_info.h"
#include "verilog/analyze/resolve.h"
#include "verilog/ast/visitors/visitor.h"
#include "verilog/ast/ast.h"
#include "verilog/build/ast_builder.h"
#include "verilog/print/print.h"
#include "verilog/transform/block_flatten.h"

using namespace std;

namespace cascade {

namespace aos {

template <typename T>
class Rewrite {
  public:
    std::string run(const ModuleDeclaration* md, size_t slot, const VarTable<T>* vt, const Identifier* clock, size_t nv_size);

  private:
    // Records variables which appear in timing control statements
    struct TriggerIndex : Visitor {
      TriggerIndex();
      ~TriggerIndex() override = default;
      std::map<std::string, const Identifier*> negedges_;
      std::map<std::string, const Identifier*> posedges_;
      void visit(const Event* e) override;
    };

    void emit_file_vars(ModuleDeclaration* res);
    void emit_state_machine_vars(ModuleDeclaration* res);
    void emit_access_vars(ModuleDeclaration* res, size_t nv_size);
    void emit_var_table(ModuleDeclaration* res, const VarTable<T>* vt);
    void emit_shadow_vars(ModuleDeclaration* res, const ModuleDeclaration* md, const VarTable<T>* vt);
    void emit_view_vars(ModuleDeclaration* res, const ModuleDeclaration* md, const VarTable<T>* vt);
    void emit_update_vars(ModuleDeclaration* res, const VarTable<T>* vt);
    void emit_state_vars(ModuleDeclaration* res);
    void emit_trigger_vars(ModuleDeclaration* res, const TriggerIndex* ti);
    void emit_open_loop_vars(ModuleDeclaration* res);

    void emit_access_logic(ModuleDeclaration* res, size_t nv_size);
    void emit_state_logic(ModuleDeclaration* res, const VarTable<T>* vt);
    void emit_trigger_logic(ModuleDeclaration* res, const TriggerIndex* ti);
    void emit_logic(ModuleDeclaration* res, const ModuleDeclaration* md, const VarTable<T>* vt, const SeqBlock* sb, const Identifier* open_loop_clock, size_t nv_size);
          
    void emit_subscript(Identifier* id, size_t idx, size_t n, const std::vector<size_t>& arity) const;
    void emit_slice(Identifier* id, size_t w, size_t i) const;
};

template <typename T>
inline std::string Rewrite<T>::run(const ModuleDeclaration* md, size_t slot, const VarTable<T>* vt, const Identifier* clock, size_t nv_size) {
  std::stringstream ss;

  // Generate index tables before doing anything even remotely invasive
  TriggerIndex ti;
  md->accept(&ti);

  // Emit a new declaration, with module name based on slot id. This
  // declaration will use the Avalon Memory-mapped slave interface.
  DeclBuilder db;
  db << "module M" << static_cast<int>(slot) << "(__clk, __in_read, __in_vid, __in_data, __in_valid, __out_data, __out_valid);" << std::endl;
  db << "input wire __clk;" << std::endl;
  db << "input wire __in_read;" << std::endl;
  db << "input wire[13:0] __in_vid;" << std::endl;
  db << "input wire[63:0] __in_data;" << std::endl;
  db << "input wire __in_valid;" << std::endl;
  db << "output wire[63:0] __out_data;" << std::endl;
  db << "output wire __out_valid;" << std::endl;
  db << "endmodule" << std::endl;
  auto *res = db.get();

  emit_access_vars(res, nv_size);
  emit_var_table(res, vt);
  emit_shadow_vars(res, md, vt);
  emit_view_vars(res, md, vt);
  emit_update_vars(res, vt);
  emit_state_vars(res);
  //emit_trigger_vars(res, &ti);
  emit_open_loop_vars(res);

  // Emit original program logic
  TextMangle<T> tm(md, vt);
  md->accept_items(&tm, res->back_inserter_items());
  
  // 
  auto pl_sb = new SeqBlock();
  for (auto i = res->begin_items(); i != res->end_items(); ) {
    // Ignore everything other than always constructs
    if (!(*i)->is(Node::Tag::always_construct)) {
      ++i;
      continue;
    }

    // Ignore combinational always constructs
    auto* ac = static_cast<AlwaysConstruct*>(*i);
    assert(ac->get_stmt()->is(Node::Tag::timing_control_statement));
    auto* tcs = static_cast<const TimingControlStatement*>(ac->get_stmt());
    assert(tcs->get_ctrl()->is(Node::Tag::event_control));
    auto* ec = static_cast<const EventControl*>(tcs->get_ctrl());
    if (ec->front_events()->get_type() == Event::Type::EDGE) {
      ++i;
      continue;
    }
      
    // Generate a state machine for this block and remove it from the AST.
    pl_sb->push_back_stmts(tcs->get_stmt()->clone());
    i = res->purge_items(i);
  }

  //emit_file_vars(res);
  emit_state_machine_vars(res);
  emit_access_logic(res, nv_size);
  emit_state_logic(res, vt);
  //emit_trigger_logic(res, &ti);
  emit_logic(res, md, vt, pl_sb, clock, nv_size);

  // Final cleanup passes
  BlockFlatten().run(res);

  // Holy cow! We're done!
  ss.str(std::string());
  ss << res;
  delete res;
  return ss.str();
}

template <typename T>
inline Rewrite<T>::TriggerIndex::TriggerIndex() : Visitor() { }

template <typename T>
inline void Rewrite<T>::TriggerIndex::visit(const Event* e) {
  assert(e->get_expr()->is(Node::Tag::identifier));
  const auto* i = static_cast<const Identifier*>(e->get_expr());
  const auto* r = Resolve().get_resolution(i);
  assert(r != nullptr);

  switch (e->get_type()) {
    case Event::Type::NEGEDGE:
      negedges_[r->front_ids()->get_readable_sid()] = r;
      break;
    case Event::Type::POSEDGE:
      posedges_[r->front_ids()->get_readable_sid()] = r;
      break;
    default:
      // Don't record untyped edges
      break;
  }
}

template <typename T>
inline void Rewrite<T>::emit_file_vars(ModuleDeclaration* res) {
  ItemBuilder ib;
  ib << "reg __fread_req[0:0];" << std::endl;
  ib << "reg __fwrite_req[0:0];" << std::endl;
  ib << "reg __f_ack[0:0];" << std::endl;
  ib << "reg[63:0] __fread_data[0:0];" << std::endl;
  ib << "reg[63:0] __fwrite_data[0:0];" << std::endl;
  
  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_state_machine_vars(ModuleDeclaration* res) {
  ItemBuilder ib;
  ib << "reg[15:0] __task_id;" << std::endl;
  ib << "reg[15:0] __task_id_reg;" << std::endl;
  ib << "reg[255:0] __task_mask;" << std::endl;
  ib << "reg[255:0] __task_eof;" << std::endl;
  
  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_access_vars(ModuleDeclaration* res, size_t nv_size) {
  ItemBuilder ib;
  
  // Emit buffer regs
  ib << "(* shreg_extract = \"no\" *) reg [" << (nv_size-1) << ":0] __read_buf [3:2];" << std::endl;
  ib << "(* shreg_extract = \"no\" *) reg [" << (nv_size-1) << ":0] __write_buf [3:2];" << std::endl;
  ib << "(* shreg_extract = \"no\" *) reg [63:0] __in_buf [3:2];" << std::endl;
  ib << "reg [63:0] __out_buf [" << ((nv_size-1)/128) << ":0];" << std::endl;
  ib << "reg [63:0] __out;" << std::endl;
  ib << "(* shreg_extract = \"no\" *) reg __out_valid_buf [3:0];" << std::endl;
  
  // Emit combinational vars
  ib << "reg [63:0] __out_buf_next [" << ((nv_size-1)/128) << ":0];" << std::endl;
  ib << "reg [63:0] __out_next;" << std::endl;
  
  // Emit interface
  ib << "wire [" << (nv_size-1) << ":0] __read;" << std::endl;
  ib << "wire [" << (nv_size-1) << ":0] __write;" << std::endl;
  ib << "wire[63:0] __in;" << std::endl;
  ib << "reg __wait;" << std::endl;
  res->push_back_items(ib.begin(), ib.end()); 
}

template <typename T>
inline void Rewrite<T>::emit_var_table(ModuleDeclaration* res, const VarTable<T>* vt) {
  ItemBuilder ib;

  // Emit the var table 
  const auto var_arity = vt->size();
  ib << "reg[63:0] __var[" << (var_arity-1) << ":0];" << std::endl;
  ib << "reg[63:0] __var_reg[" << (var_arity-1) << ":0];" << std::endl;
  // Emit the feof table
  ib << "reg[63:0] __feof;" << std::endl;
  ib << "reg[63:0] __feof_reg = 0;" << std::endl;
  ib << "reg[5:0] __eof_addr;" << std::endl;

  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_shadow_vars(ModuleDeclaration* res, const ModuleDeclaration* md, const VarTable<T>* vt) {
  ModuleInfo info(md);

  // Index the stateful elements in the variable table
  std::map<std::string, typename VarTable<T>::const_iterator> vars;
  for (auto v = vt->begin(), ve = vt->end(); v != ve; ++v) {
    if (info.is_stateful(v->first)) {
      vars.insert(make_pair(v->first->front_ids()->get_readable_sid(), v));
    }
  }

  // Emit a shadow variable for every element with name suffixed by _next.
  ItemBuilder ib;
  for (const auto& v : vars) {
    const auto itr = v.second;
    assert(itr->first->get_parent() != nullptr);
    assert(itr->first->get_parent()->is(Node::Tag::reg_declaration));
    
    auto* rd = static_cast<const RegDeclaration*>(itr->first->get_parent())->clone();
    rd->get_id()->purge_ids();
    rd->get_id()->push_front_ids(new Id(v.first + "_next"));
    rd->replace_attrs(new Attributes());
    rd->replace_val(nullptr);
    ib << rd << std::endl;
    delete rd;
  }

  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_view_vars(ModuleDeclaration* res, const ModuleDeclaration* md, const VarTable<T>* vt) {
  ModuleInfo info(md);

  // Index both inputs and the stateful elements in the variable table
  std::map<std::string, typename VarTable<T>::const_iterator> vars;
  for (auto v = vt->begin(), ve = vt->end(); v != ve; ++v) {
    if (info.is_input(v->first) || info.is_stateful(v->first)) {
      vars.insert(make_pair(v->first->front_ids()->get_readable_sid(), v));
    }
  }

  // Emit views for these variables
  ItemBuilder ib;
  for (const auto& v : vars) {
    const auto itr = v.second;
    assert(itr->first->get_parent() != nullptr);
    assert(itr->first->get_parent()->is_subclass_of(Node::Tag::declaration));
    const auto* d = static_cast<const Declaration*>(itr->first->get_parent());

    auto* nd = new NetDeclaration(
      new Attributes(), 
      d->get_id()->clone(),
      d->get_type(),
      d->is_non_null_dim() ? d->clone_dim() : nullptr
    );
    ib << nd << std::endl;
    delete nd;
    
    for (size_t i = 0, ie = itr->second.elements; i < ie; ++i) {
      auto* lhs = itr->first->clone();
      lhs->purge_dim();
      emit_subscript(lhs, i, ie, Evaluate().get_arity(itr->first));
      ib << "assign " << lhs << " = {";
      delete lhs;
      
      for (size_t j = 0, je = itr->second.words_per_element; j < je; ) {
        ib << "__var[" << (itr->second.begin + (i+1)*je-j-1) << "]";
        if (++j != je) {
          ib << ",";
        }
      }
      ib << "};" << std::endl;
    }
  }

  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_update_vars(ModuleDeclaration* res, const VarTable<T>* vt) {
  ItemBuilder ib;

  const auto update_arity = std::max(static_cast<size_t>(8), vt->size());
  ib << "reg [" << (update_arity-1) << ":0] __update_queue;" << std::endl;
  ib << "reg __there_are_updates;" << std::endl;
  ib << "reg __apply_updates;" << std::endl;
  
  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_state_vars(ModuleDeclaration* res) {
  ItemBuilder ib;

  ib << "reg __there_were_tasks;" << std::endl;
  ib << "reg __there_were_tasks_reg;" << std::endl;
  ib << "wire __continue;" << std::endl;
  ib << "wire __reset;" << std::endl;

  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_trigger_vars(ModuleDeclaration* res, const TriggerIndex* ti) {
  ItemBuilder ib;

  // Index triggers
  std::map<std::string, const Identifier*> vars;
  for (auto& e : ti->negedges_) {
    vars[e.first] = e.second;
  }
  for (auto& e : ti->posedges_) {
    vars[e.first] = e.second;
  }

  // Emit variables for storing previous values of trigger variables
  for (const auto& v : vars) {
    assert(v.second->get_parent() != nullptr);
    assert(v.second->get_parent()->is_subclass_of(Node::Tag::declaration));
    const auto* d = static_cast<const Declaration*>(v.second->get_parent());

    auto* rd = new RegDeclaration(
      new Attributes(),
      new Identifier(v.first + "_prev"),
      d->get_type(),
      d->is_non_null_dim() ? d->clone_dim() : nullptr,
      nullptr
    );
    ib << rd << std::endl;
    delete rd; 
  }

  // Emit edge variables (these should be sorted determinstically by virtue of
  // how these sets were built)
  for (const auto& e : ti->negedges_) {
    ib << "wire " << e.first << "_negedge;" << std::endl;
  }
  for (auto& e : ti->posedges_) {
    ib << "wire " << e.first << "_posedge;" << std::endl;
  }
  
  // Emit var for tracking whether any triggers just occurred
  ib << "wire __any_triggers;" << std::endl;

  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_open_loop_vars(ModuleDeclaration* res) {
  ItemBuilder ib;

  ib << "reg[31:0] __open_loop = 0;" << std::endl;
  ib << "reg __open_loop_tick;" << std::endl;

  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_access_logic(ModuleDeclaration* res, size_t nv_size) {
  ItemBuilder ib;
  
  ib << "always @(posedge __clk) begin: __buf_block" << std::endl;
  ib << "__read_buf[3] <= (__in_valid && __in_read) << __in_vid;" << std::endl;
  ib << "__read_buf[2] <= __read_buf[3];" << std::endl;
  ib << "__write_buf[3] <= (__in_valid && (!__in_read)) << __in_vid;" << std::endl;
  ib << "__write_buf[2] <= __write_buf[3];" << std::endl;
  ib << "__in_buf[3] <= __in_data;" << std::endl;
  ib << "__in_buf[2] <= __in_buf[3];" << std::endl;
  ib << "end" << std::endl;
  
  ib << "assign __read = __read_buf[2];" << std::endl;
  ib << "assign __write = __write_buf[2];" << std::endl;
  ib << "assign __in = __in_buf[2];" << std::endl;
  
  res->push_back_items(ib.begin(), ib.end()); 
}

template <typename T>
inline void Rewrite<T>::emit_state_logic(ModuleDeclaration* res, const VarTable<T>* vt) {
  ItemBuilder ib;

  ib << "assign __continue = __read[" << vt->resume_index() << "];" << std::endl;
  ib << "assign __reset = __read[" << vt->reset_index() << "];" << std::endl;

  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_trigger_logic(ModuleDeclaration* res, const TriggerIndex* ti) {
  ItemBuilder ib;

  // Index trigger variables
  std::set<std::string> vars;
  for (const auto& e : ti->negedges_) {
    vars.insert(e.first);
  }
  for (const auto& e : ti->posedges_) {
    vars.insert(e.first);
  }

  // Emit updates for trigger variables
  ib << "always @(posedge __clk) begin" << std::endl;
  for (const auto& v : vars) {
    ib << v << "_prev <= " << v << ";" << std::endl;
  }
  ib << "end" << std::endl;

  // Emit edge variables (these should be sorted determinstically by virtue of
  // how these sets were built)
  for (const auto& e : ti->negedges_) {
    ib << "assign " << e.first << "_negedge = (" << e.first << "_prev == 1) && (" << e.first << " == 0);" << std::endl;
  }
  for (auto& e : ti->posedges_) {
    ib << "assign " << e.first << "_posedge = (" << e.first << "_prev == 0) && (" << e.first << " == 1);" << std::endl;
  }
  
  // Emit logic for tracking whether any triggers just occurred
  if (ti->posedges_.empty() && ti->negedges_.empty()) {
    ib << "assign __any_triggers = 0;" << std::endl;
  } else {
    ib << "assign __any_triggers = |{";
    for (auto i = ti->negedges_.begin(), ie = ti->negedges_.end(); i != ie; ) {
      ib << i->first << "_negedge";
      if ((++i != ie) || !ti->posedges_.empty()) {
        ib << ",";
      }
    }
    for (auto i = ti->posedges_.begin(), ie = ti->posedges_.end(); i != ie; ) {
      ib << i->first << "_posedge";
      if (++i != ie) {
        ib << ",";
      } 
    }
    ib << "};" << std::endl;
  }

  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_logic(ModuleDeclaration* res, const ModuleDeclaration* md, const VarTable<T>* vt, const SeqBlock* sb, const Identifier* clock, size_t nv_size) {
  ModuleInfo info(md);

  // Index both inputs and stateful elements in the variable table 
  std::map<size_t, typename VarTable<T>::const_iterator> vars, vvars;
  for (auto t = vt->begin(), te = vt->end(); t != te; ++t) {
    if (info.is_input(t->first) || info.is_stateful(t->first)) {
      vars[t->second.begin] = t;
    }
  }
  
  // Index variables in the task variable table
  std::map<size_t, typename VarTable<T>::const_iterator> task_vars;
  for (auto t = vt->begin_task(), te = vt->end_task(); t != te; ++t) {
    task_vars[t->second.begin] = t;
  }

  ItemBuilder ib;
  ib << "always @(posedge __clk) begin: __compute_block" << std::endl;
  
  // Init values
  ib << "integer i0;" << std::endl;
  ib << "for (i0 = " << (vt->debug_index()+1) << "; ";
  ib << "i0 < " << vt->size() << "; i0 = i0 + 1) begin" << std::endl;
  ib << "__var[i0] = __var_reg[i0];" << std::endl;
  ib << "end" << std::endl;
  ib << "__there_are_updates <= 0;" << std::endl;
  ib << "__there_were_tasks = 0;" << std::endl;
  ib << "__update_queue = 0;" << std::endl;
  ib << "__task_id = 0;" << std::endl;
  ib << "__feof = __feof_reg;" << std::endl;
  
  // Emit program logic
  ib << sb << std::endl;
  
  // Emit variable logic
  ib << "__open_loop_tick = ((!__there_were_tasks) && (__open_loop > 0));" << std::endl;
  ib << "__apply_updates = (__read[" << vt->apply_update_index() << "] || __open_loop_tick);" << std::endl;
  ib << "__open_loop <= (__read[" << vt->open_loop_index() << "] ? __in : (__open_loop_tick ? (__open_loop - 1) : __open_loop));" << std::endl;
  ib << "__task_id_reg <= __task_id;" << std::endl;
  ib << "__there_were_tasks_reg <= __there_were_tasks;" << std::endl;
  for (const auto& v : vars) {
    const auto itr = v.second;
    const auto arity = Evaluate().get_arity(itr->first);
    const auto w = itr->second.bits_per_element;
    auto idx = itr->second.begin;

    for (size_t i = 0, ie = itr->second.elements; i < ie; ++i) {
      for (size_t j = 0, je = itr->second.words_per_element; j < je; ++j) {
        ib << "__var_reg[" << idx << "]";
        if (w < 64) ib << "[" << (w-1) << ":0]";
        ib << " <= ";
        /*if ((clock != nullptr) && (itr->first == clock)) {
          ib << "__open_loop_tick ? (~" << itr->first->front_ids()->get_readable_sid() << ") : ";
        }*/
        if (!info.is_volatile(itr->first)) {
          ib << "__read[" << idx << "] ? __in : ";
        }
        if (info.is_stateful(itr->first)) {
          auto* id = new Identifier(itr->first->front_ids()->get_readable_sid() + "_next");
          emit_subscript(id, i, ie, arity);
          emit_slice(id, w, j);
          ib << "__apply_updates ? ";
          ib << "(__update_queue[" << idx << "] ? " << id << " : __var[" << idx << "]) : ";
          delete id;
        }
        ib << "__var_reg[" << idx << "];" << std::endl;
        ++idx;
      }
    }
  }
  
  for (const auto& v : task_vars) {
    const auto itr = v.second;
    const auto arity = Evaluate().get_arity(itr->first);
    const auto w = itr->second.bits_per_element;
    auto idx = itr->second.begin;

    for (size_t i = 0, ie = itr->second.elements; i < ie; ++i) {
      for (size_t j = 0, je = itr->second.words_per_element; j < je; ++j) {
        ib << "__var_reg[" << idx << "]";
        if (w < 64) ib << "[" << (w-1) << ":0]";
        ib << " <= ";
        ib << "__read[" << idx << "] ? __in : ";
        ib << "__var_reg[" << idx << "];" << std::endl;
        ++idx;
      }
    }
  }

  ib << "if (__apply_updates) __feof_reg <= __feof;" << std::endl;
  ib << "if (__read[" << vt->feof_index() << "] && !__in[0]) begin" << std::endl;
  ib << "__feof_reg[__in[7:2]] <= __in[1];" << std::endl;
  ib << "end" << std::endl;
  ib << "if (__reset) __feof_reg <= 0;" << std::endl;
  ib << "if (__apply_updates || __reset) begin" << std::endl;
  ib << "__task_mask <= 0;" << std::endl;
  ib << "__task_eof <= 0;" << std::endl;
  ib << "end" << std::endl;
  ib << "end" << std::endl;    

  // Index the elements in the variable table which aren't inputs or stateful.
  std::map<size_t, typename VarTable<T>::const_iterator> outputs;
  for (auto t = vt->begin(), te = vt->end(); t != te; ++t) {
    if (!info.is_input(t->first) && !info.is_stateful(t->first)) {
      outputs[t->second.begin] = t;
    }
  }
  
  size_t buf_idx;
  ib << "always @(posedge __clk) begin: __out_buf_block" << std::endl;
  //ib << "always @(*) begin: __out_buf_reduction" << std::endl;
  
  ib << "integer t0;" << std::endl;
  ib << "integer t1;" << std::endl;
  ib << "integer t2;" << std::endl;
  ib << "__wait = (__open_loop > 0) && (!__there_were_tasks_reg);" << std::endl;  // __any_triggers
  
  ib << "for (t0 = 0; t0 <= " << ((nv_size-1)/128) << "; t0 = t0 + 1) begin" << std::endl;
  ib << "__out_buf_next[t0] = 0;" << std::endl;
  ib << "end" << std::endl;
  
  buf_idx = 0;
  ib << "__out_buf_next[" << buf_idx << "] = __out_buf_next[" << buf_idx << "] | ";
  ib << "(__write[" << vt->there_are_updates_index();
  ib << "] ? __there_are_updates : 0);" << std::endl;
  
  ib << "__out_buf_next[" << buf_idx << "] = __out_buf_next[" << buf_idx << "] | ";
  ib << "(__write[" << vt->there_were_tasks_index();
  ib << "] ? __task_id_reg : 0);" << std::endl;
  
  ib << "__out_buf_next[" << buf_idx << "] = __out_buf_next[" << buf_idx << "] | ";
  ib << "(__write[" << vt->open_loop_index();
  ib << "] ? __open_loop : 0);" << std::endl;
  
  ib << "__out_buf_next[" << buf_idx << "] = __out_buf_next[" << buf_idx << "] | ";
  ib << "(__write[" << vt->wait_index();
  ib << "] ? __wait : 0);" << std::endl;
  
  for (const auto& v : vars) {
    const auto itr = v.second;
    const auto arity = Evaluate().get_arity(itr->first);
    const auto w = itr->second.bits_per_element;
    auto idx = itr->second.begin;

    for (size_t i = 0, ie = itr->second.elements; i < ie; ++i) {
      for (size_t j = 0, je = itr->second.words_per_element; j < je; ++j) {
        buf_idx = idx/128;
        ib << "__out_buf_next[" << buf_idx << "] = ";
        ib << "__out_buf_next[" << buf_idx << "] | ";
        ib << "(__write[" << idx << "] ? ";
        ib << "__var_reg[" << idx << "]";
        if (w < 64) ib << "[" << (w-1) << ":0]";
        ib << " : 0);" << std::endl;
        
        ++idx;
      }
    }
  }
  
  for (const auto& o : outputs) {
    const auto itr = o.second;
    assert(itr->second.elements == 1);
    const auto w = itr->second.bits_per_element;
    for (size_t i = 0; i < itr->second.words_per_element; ++i) {
      buf_idx = (itr->second.begin+i)/128;
      ib << "__out_buf_next[" << buf_idx << "] = ";
      ib << "__out_buf_next[" << buf_idx << "] | ";
      ib << "(__write[" << (itr->second.begin+i) << "] ? ";

      auto* id = itr->first->clone();
      id->purge_dim();
      emit_slice(id, w, i);
      ib << id << " : 0);" << std::endl;

      delete id;
    }
  }
  
  ib << "__out_next = 0;" << std::endl;
  ib << "for (t2 = 0; t2 <= " << ((nv_size-1)/128) << "; t2 = t2 + 1) begin" << std::endl;
  ib << "__out_next = __out_next | __out_buf[t2];" << std::endl;
  ib << "end" << std::endl;
  //ib << "end" << std::endl;
  
  //ib << "always @(posedge __clk) begin: __out_buf_block" << std::endl;
  //ib << "integer t1;" << std::endl;
  ib << "for (t1 = 0; t1 <= " << ((nv_size-1)/128) << "; t1 = t1 + 1) begin" << std::endl;
  ib << "__out_buf[t1] <= __out_buf_next[t1];" << std::endl;
  ib << "end" << std::endl;
  ib << "__out <= __out_next;" << std::endl;
  ib << "__out_valid_buf[3] <= __in_valid & (!__in_read);" << std::endl;
  ib << "__out_valid_buf[2] <= __out_valid_buf[3];" << std::endl;
  ib << "__out_valid_buf[1] <= __out_valid_buf[2];" << std::endl;
  ib << "__out_valid_buf[0] <= __out_valid_buf[1];" << std::endl;
  ib << "end" << std::endl;
  
  ib << "assign __out_data = __out;" << std::endl;
  ib << "assign __out_valid = __out_valid_buf[0];" << std::endl;

  res->push_back_items(ib.begin(), ib.end());
}

template <typename T>
inline void Rewrite<T>::emit_subscript(Identifier* id, size_t idx, size_t n, const std::vector<size_t>& arity) const {
  for (auto a : arity) {
    n /= a;
    const auto i = idx / n;
    idx -= i*n;
    id->push_back_dim(new Number(Bits(8*sizeof(T), i)));
  }
}

template <typename T>
inline void Rewrite<T>::emit_slice(Identifier* id, size_t w, size_t i) const {
  const auto upper = std::min(8*sizeof(T)*(i+1),w);
  const auto lower = 8*sizeof(T)*i;
  if (upper == 1) {
    // Do nothing 
  } else if (upper > lower) {
    id->push_back_dim(new RangeExpression(upper, lower));
  } else {
    id->push_back_dim(new Number(Bits(8*sizeof(T), lower)));
  }
}

} // namespace aos

} // namespace cascade

#endif
