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

#ifndef CASCADE_SRC_TARGET_CORE_AOS_AOS_LOGIC_H
#define CASCADE_SRC_TARGET_CORE_AOS_AOS_LOGIC_H

#include <cassert>
#include <functional>
#include <unordered_map>
#include <vector>
#include "common/bits.h"
#include "target/core.h"
#include "target/core/aos/var_table.h"
#include "target/core/common/interfacestream.h"
#include "target/core/common/printf.h"
#include "target/core/common/scanf.h"
#include "target/input.h"
#include "target/state.h"
#include "verilog/ast/ast.h"
#include "verilog/analyze/evaluate.h"
#include "verilog/analyze/module_info.h"
#include "verilog/ast/visitors/visitor.h"

namespace cascade {

namespace aos {

template <typename T>
class AosLogic : public Logic {
  public:
    // Typedefs:
    typedef std::function<void()> Callback;

    // Constructors:
    AosLogic(Interface* interface, ModuleDeclaration* md);
    ~AosLogic() override;

    // Configuration Methods:
    AosLogic& set_input(const Identifier* id, VId vid);
    AosLogic& set_state(bool is_volatile, const Identifier* id, VId vid);
    AosLogic& set_output(const Identifier* id, VId vid);
    AosLogic& index_tasks();
    AosLogic& set_callback(Callback cb);

    // Configuraton Properties:
    VarTable<T>* get_table();
    const VarTable<T>* get_table() const;

    // Core Interface:
    State* get_state() override;
    void set_state(const State* s) override;
    Input* get_input() override;
    void set_input(const Input* i) override;
    void finalize() override;

    void read(VId id, const Bits* b) override;
    void evaluate() override;
    bool there_are_updates() const override;
    void update() override;
    bool there_were_tasks() const override;

    size_t open_loop(VId clk, bool val, size_t itr) override;

    // Optimization Properties:
    const Identifier* open_loop_clock();

  private:
    // Compiler State:
    Callback cb_;

    // Source Management:
    ModuleDeclaration* src_;
    std::vector<const Identifier*> inputs_;
    std::unordered_map<VId, const Identifier*> state_;
    std::vector<std::pair<const Identifier*, VId>> outputs_;
    std::vector<const SystemTaskEnableStatement*> tasks_;

    // Control State:
    bool there_were_tasks_;
    VarTable<T> table_;
    std::unordered_map<FId, interfacestream*> streams_;

    // Control Helpers:
    interfacestream* get_stream(FId fd);
    bool handle_tasks();
    
    // Feof Helpers:
    void set_feof_mask(FId fd, bool val);

    // Indexes system tasks and inserts the identifiers which appear in those
    // tasks into the variable table.
    class Inserter : public Visitor {
      public:
        explicit Inserter(AosLogic* av);
        ~Inserter() override = default;
      private:
        AosLogic* av_;
        bool in_args_;
        void visit(const Identifier* id) override;
        void visit(const FeofExpression* fe) override;
        void visit(const DebugStatement* ds) override;
        void visit(const FflushStatement* fs) override;
        void visit(const FinishStatement* fs) override;
        void visit(const FseekStatement* fs) override;
        void visit(const GetStatement* gs) override;
        void visit(const PutStatement* ps) override;
        void visit(const RestartStatement* rs) override;
        void visit(const RetargetStatement* rs) override;
        void visit(const SaveStatement* ss) override;
        void visit(const YieldStatement* ys) override;
    };

    // Synchronizes the state of streams opened with fopen
    class StreamSync : public Visitor {
    public:
      explicit StreamSync(AosLogic* av);
      ~StreamSync() override = default;
      private:
        AosLogic* av_;
        void visit(const FopenExpression* fe) override;
    };
    
    // Synchronizes the locations in the variable table which correspond to the
    // identifiers which appear in an AST subtree. 
    class ValSync : public Visitor {
    public:
      explicit ValSync(AosLogic* av);
      ~ValSync() override = default;
      private:
        AosLogic* av_;
        void visit(const Identifier* id) override;
    };

    // Evaluation Helpers:
    Evaluate eval_;
    ValSync sync_;
    Scanf scanf_;
    Printf printf_;
};

template <typename T>
inline AosLogic<T>::AosLogic(Interface* interface, ModuleDeclaration* src) : Logic(interface), sync_(this) { 
  src_ = src;
  cb_ = nullptr;
  tasks_.push_back(nullptr);
  
  eval_.set_feof_handler([this](Evaluate* eval, const FeofExpression* fe) {
    fe->accept_fd(&sync_);
    const auto fd = eval_.get_value(fe->get_fd()).to_uint();
    return get_stream(fd)->eof();
  });
}

template <typename T>
inline AosLogic<T>::~AosLogic() {
  if (cb_ != nullptr) {
    cb_();
  }
  delete src_;
  for (auto& s : streams_) {
    delete s.second;
  }
}

template <typename T>
inline AosLogic<T>& AosLogic<T>::set_input(const Identifier* id, VId vid) {
  if (table_.find(id) == table_.end()) {
    table_.insert(id);
  }
  if (inputs_.size() <= vid) {
    inputs_.resize(vid+1, nullptr);
  }
  inputs_[vid] = id;
  return *this;
}

template <typename T>
inline AosLogic<T>& AosLogic<T>::set_state(bool is_volatile, const Identifier* id, VId vid) {
  if (table_.find(id) == table_.end()) {
    table_.insert(id);
  }   
  if (!is_volatile) {
    state_.insert(std::make_pair(vid, id));
  }
  return *this;
}

template <typename T>
inline AosLogic<T>& AosLogic<T>::set_output(const Identifier* id, VId vid) {
  if (table_.find(id) == table_.end()) { 
    table_.insert(id);
  }
  outputs_.push_back(std::make_pair(id, vid));
  return *this;
}

template <typename T>
inline AosLogic<T>& AosLogic<T>::index_tasks() {
  Inserter i(this);
  src_->accept(&i);
  return *this;
}

template <typename T>
inline AosLogic<T>& AosLogic<T>::set_callback(Callback cb) {
  cb_ = cb;
  return *this;
}

template <typename T>
inline VarTable<T>* AosLogic<T>::get_table() {
  return &table_;
}

template <typename T>
inline const VarTable<T>* AosLogic<T>::get_table() const {
  return &table_;
}

template <typename T>
inline State* AosLogic<T>::get_state() {
  auto* s = new State();
  for (const auto& sv : state_) {
    table_.read_var(sv.second);
    s->insert(sv.first, eval_.get_array_value(sv.second));
  }
  return s;
}

template <typename T>
inline void AosLogic<T>::set_state(const State* s) {
  // Reset state, drop updates, and pause execution
  table_.write_control_var(table_.reset_index(), 1);
  for (const auto& sv : state_) {
    const auto itr = s->find(sv.first);
    if (itr != s->end()) {
      table_.write_var(sv.second, itr->second);
    }
  }
  // Reset state, drop updates, and re-enable execution
  table_.write_control_var(table_.reset_index(), 1);
  table_.write_control_var(table_.resume_index(), 1);
}

template <typename T>
inline Input* AosLogic<T>::get_input() {
  auto* i = new Input();
  for (size_t v = 0, ve = inputs_.size(); v < ve; ++v) {
    const auto* id = inputs_[v];
    if (id == nullptr) {
      continue;
    }
    table_.read_var(id);
    i->insert(v, eval_.get_value(id));
  }
  return i;
}

template <typename T>
inline void AosLogic<T>::set_input(const Input* i) {
  // Reset state, drop updates, and pause execution
  table_.write_control_var(table_.reset_index(), 1);
  for (size_t v = 0, ve = inputs_.size(); v < ve; ++v) {
    const auto* id = inputs_[v];
    if (id == nullptr) {
      continue;
    }
    const auto itr = i->find(v);
    if (itr != i->end()) {
      table_.write_var(id, itr->second);
    }
  }
  // Reset state, drop updates, and re-enable execution
  table_.write_control_var(table_.reset_index(), 1);
  table_.write_control_var(table_.resume_index(), 1);
}

template <typename T>
inline void AosLogic<T>::finalize() {
  // Note: We ignore the six standard streams, which can never be in the eof
  // state.
  // Note: Referencing a file descriptor which was not returned by a call to
  // fopen is undefined. Iterating over these variable is sufficent for
  // synchronizing stream state.
  StreamSync ss(this);
  src_->accept(&ss);
}

template <typename T>
inline void AosLogic<T>::read(VId id, const Bits* b) {
  assert(id < inputs_.size());
  assert(inputs_[id] != nullptr);
  table_.write_var(inputs_[id], *b);
}

template <typename T>
inline void AosLogic<T>::evaluate() {
  there_were_tasks_ = false;
  while (handle_tasks()) {
    table_.write_control_var(table_.resume_index(), 1);
  }
  for (const auto& o : outputs_) {
    table_.read_var(o.first);
    interface()->write(o.second, &eval_.get_value(o.first));
  }
}

template <typename T>
inline bool AosLogic<T>::there_are_updates() const {
  // Read there_are_updates flag
  return table_.read_control_var(table_.there_are_updates_index()) != 0;
}

template <typename T>
inline void AosLogic<T>::update() {
  table_.write_control_var(table_.apply_update_index(), 1);
  evaluate();
}

template <typename T>
inline bool AosLogic<T>::there_were_tasks() const {
  return there_were_tasks_;
}

template <typename T>
inline size_t AosLogic<T>::open_loop(VId clk, bool val, size_t itr) {
  // The fpga already knows the value of clk. We can ignore it.
  (void) clk;
  (void) val;

  there_were_tasks_ = false;

  // Setting the open loop variable allows the continue flag to span clock
  // ticks.  Loop here either until control returns without having hit a task
  // (indicating that we've finished) or it trips a task that requires
  // immediate attention.
  table_.write_control_var(table_.open_loop_index(), itr);
  while (handle_tasks() && !there_were_tasks_) {
    table_.write_control_var(table_.resume_index(), 1);
  }

  // If we hit a task that requires immediate attention, clear the open loop
  // counter, finish out this clock, and return the number of iterations that
  // we ran for. Otherwise, we finished our quota.
  if (there_were_tasks_) {
    const auto res = table_.read_control_var(table_.open_loop_index());
    table_.write_control_var(table_.open_loop_index(), 0);
    while (handle_tasks()) {
      table_.write_control_var(table_.resume_index(), 1);
    }
    // Note: res was recorded *before* the completion of the current iteration
    return itr-res+1;
  } else {
    return itr;
  }
}

template <typename T>
inline const Identifier* AosLogic<T>::open_loop_clock() {
  ModuleInfo info(src_);
  if (info.inputs().size() != 1) {
    return nullptr;
  }
  if (eval_.get_width(*info.inputs().begin()) != 1) {
    return nullptr;
  }
  if (!info.outputs().empty()) {
    return nullptr;
  }
  return *ModuleInfo(src_).inputs().begin();
}

template <typename T>
inline interfacestream* AosLogic<T>::get_stream(FId fd) {
  const auto itr = streams_.find(fd);
  if (itr != streams_.end()) {
    return itr->second;
  }
  auto* is = new interfacestream(interface(), fd);
  streams_[fd] = is;
  return is;
}

template <typename T>
inline bool AosLogic<T>::handle_tasks() {
  // Block until execution has paused
  while (table_.read_control_var(table_.wait_index()));

  auto task_id = table_.read_control_var(table_.there_were_tasks_index());
  if (task_id == 0) {
    return false;
  }
  assert(task_id != 65535);
  const auto* task = tasks_[task_id];

  switch (task->get_tag()) {
    case Node::Tag::debug_statement: {
      const auto* ds = static_cast<const DebugStatement*>(task);
      std::stringstream ss;
      ss << ds->get_arg();
      interface()->debug(eval_.get_value(ds->get_action()).to_uint(), ss.str());
      break;
    }
    case Node::Tag::finish_statement: {
      const auto* fs = static_cast<const FinishStatement*>(task);
      fs->accept_arg(&sync_);
      interface()->finish(eval_.get_value(fs->get_arg()).to_uint());
      there_were_tasks_ = true;
      break;
    }
    case Node::Tag::fflush_statement: {
      const auto* fs = static_cast<const FflushStatement*>(task);
      fs->accept_fd(&sync_);
      const auto fd = eval_.get_value(fs->get_fd()).to_uint();
      auto* is = get_stream(fd);
      
      is->clear();
      is->flush();
      set_feof_mask(fd, is->eof());

      break;
    }
    case Node::Tag::fseek_statement: {
      const auto* fs = static_cast<const FseekStatement*>(task);
      fs->accept_fd(&sync_);
      const auto fd = eval_.get_value(fs->get_fd()).to_uint();
      auto* is = get_stream(fd);
      
      fs->accept_offset(&sync_);
      const auto offset = eval_.get_value(fs->get_offset()).to_uint();
      const auto op = eval_.get_value(fs->get_op()).to_uint();
      const auto way = (op == 0) ? std::ios_base::beg : (op == 1) ? std::ios_base::cur : std::ios_base::end;
      
      is->clear();
      is->seekg(offset, way); 
      is->seekp(offset, way); 
      set_feof_mask(fd, is->eof());

      break;
    }
    case Node::Tag::get_statement: {
      const auto* gs = static_cast<const GetStatement*>(task);
      gs->accept_fd(&sync_);
      const auto fd = eval_.get_value(gs->get_fd()).to_uint();
      auto* is = get_stream(fd);
      
      scanf_.read_without_update(*is, &eval_, gs);
      if (gs->is_non_null_var()) {
        const auto* r = Resolve().get_resolution(gs->get_var());
        assert(r != nullptr);
        table_.write_var(r, scanf_.get());
      }
      if (is->eof()) {
        set_feof_mask(fd, true);
      }

      break;
    }  
    case Node::Tag::put_statement: {
      const auto* ps = static_cast<const PutStatement*>(task);
      ps->accept_fd(&sync_);
      const auto fd = eval_.get_value(ps->get_fd()).to_uint();
      auto* is = get_stream(fd);
      
      ps->accept_expr(&sync_);
      printf_.write(*is, &eval_, ps);
      if (is->eof()) {
        set_feof_mask(fd, true);
      }

      break;
    }
    case Node::Tag::restart_statement: {
      const auto* rs = static_cast<const RestartStatement*>(task);
      interface()->restart(rs->get_arg()->get_readable_val());
      there_were_tasks_ = true;
      break;
    }
    case Node::Tag::retarget_statement: {
      const auto* rs = static_cast<const RetargetStatement*>(task);
      interface()->retarget(rs->get_arg()->get_readable_val());
      there_were_tasks_ = true;
      break;
    }
    case Node::Tag::save_statement: {
      const auto* ss = static_cast<const SaveStatement*>(task);
      interface()->save(ss->get_arg()->get_readable_val());
      there_were_tasks_ = true;
      break;
    }
    case Node::Tag::yield_statement: {
      const auto* ss = static_cast<const YieldStatement*>(task);
      interface()->yield();
      there_were_tasks_ = true;
      break;
    }
    default:
      assert(false);
      break;
  }
  return true;
}

template <typename T>
inline void AosLogic<T>::set_feof_mask(FId fd, bool val) {
  const auto fid = fd & 0x7fff'ffff;
  table_.write_control_var(table_.feof_index(), (fid << 1) | (val ? 1 : 0));
}

template <typename T>
inline AosLogic<T>::Inserter::Inserter(AosLogic* av) : Visitor() {
  av_ = av;
  in_args_ = false;
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const Identifier* id) {
  Visitor::visit(id);
  const auto* r = Resolve().get_resolution(id);
  if (in_args_ && (av_->table_.find(r) == av_->table_.end())) {
    av_->table_.insert(r);
  }
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const FeofExpression* fe) {
  // Don't insert this into the task index
  in_args_ = true;
  fe->accept_fd(this);
  in_args_ = false;
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const DebugStatement* ds) {
  av_->tasks_.push_back(ds);
  // Don't descend, there aren't any expressions below here
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const FflushStatement* fs) {
  av_->tasks_.push_back(fs);
  in_args_ = true;
  fs->accept_fd(this);
  in_args_ = false;
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const FinishStatement* fs) {
  av_->tasks_.push_back(fs);
  in_args_ = true;
  fs->accept_arg(this);
  in_args_ = false;
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const FseekStatement* fs) {
  av_->tasks_.push_back(fs);
  in_args_ = true;
  fs->accept_fd(this);
  in_args_ = false;
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const GetStatement* gs) {
  av_->tasks_.push_back(gs);
  in_args_ = true;
  gs->accept_fd(this);
  in_args_ = false;
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const PutStatement* ps) {
  av_->tasks_.push_back(ps);
  in_args_ = true;
  ps->accept_fd(this);
  ps->accept_expr(this);
  in_args_ = false;
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const RestartStatement* rs) {
  av_->tasks_.push_back(rs);
  in_args_ = true;
  rs->accept_arg(this);
  in_args_ = false;
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const RetargetStatement* rs) {
  av_->tasks_.push_back(rs);
  in_args_ = true;
  rs->accept_arg(this);
  in_args_ = false;
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const SaveStatement* ss) {
  av_->tasks_.push_back(ss);
  in_args_ = true;
  ss->accept_arg(this);
  in_args_ = false;
}

template <typename T>
inline void AosLogic<T>::Inserter::visit(const YieldStatement* ys) {
  av_->tasks_.push_back(ys);
}

template <typename T>
inline AosLogic<T>::StreamSync::StreamSync(AosLogic* av) : Visitor() {
  av_ = av;
}

template <typename T>
inline void AosLogic<T>::StreamSync::visit(const FopenExpression* fe) {
  assert(fe->get_parent()->is_subclass_of(Node::Tag::declaration));
  const auto* d = static_cast<const Declaration*>(fe->get_parent());
  d->accept_id(&av_->sync_);
  const auto fd = av_->eval_.get_value(d->get_id()).to_uint();
  
  auto* is = av_->get_stream(fd);
  is->peek();
  av_->set_feof_mask(fd, is->eof());
}

template <typename T>
inline AosLogic<T>::ValSync::ValSync(AosLogic* av) : Visitor() {
  av_ = av;
}

template <typename T>
inline void AosLogic<T>::ValSync::visit(const Identifier* id) {
  id->accept_dim(this);
  const auto* r = Resolve().get_resolution(id);
  assert(r != nullptr);
  assert(av_->table_.find(r) != av_->table_.end());
  av_->table_.read_var(r);
}

} // namespace aos

} // namespace cascade

#endif
