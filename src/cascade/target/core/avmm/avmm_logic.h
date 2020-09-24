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

#ifndef CASCADE_SRC_TARGET_CORE_AVMM_AVMM_LOGIC_H
#define CASCADE_SRC_TARGET_CORE_AVMM_AVMM_LOGIC_H

#include <cassert>
#include <functional>
#include <unordered_map>
#include <vector>
#include "common/bits.h"
#include "target/core.h"
#include "target/core/avmm/var_table.h"
#include "target/core/common/interfacestream.h"
#include "target/core/common/printf.h"
#include "target/core/common/scanf.h"
#include "target/input.h"
#include "target/state.h"
#include "verilog/ast/ast.h"
#include "verilog/analyze/evaluate.h"
#include "verilog/analyze/module_info.h"
#include "verilog/ast/visitors/visitor.h"

namespace cascade::avmm {

template <size_t V, typename A, typename T>
class AvmmLogic : public Logic {
  public:
    // Typedefs:
    typedef std::function<void()> Callback;

    // Constructors:
    AvmmLogic(Interface* interface, ModuleDeclaration* md, size_t slot);
    ~AvmmLogic() override;

    // Configuration Methods:
    AvmmLogic& set_input(const Identifier* id, VId vid);
    AvmmLogic& set_state(bool is_volatile, const Identifier* id, VId vid);
    AvmmLogic& set_output(const Identifier* id, VId vid);
    AvmmLogic& index_tasks();
    AvmmLogic& set_callback(Callback cb);

    // Configuraton Properties:
    VarTable<V,A,T>* get_table();
    const VarTable<V,A,T>* get_table() const;

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
    size_t slot_;

    // Source Management:
    ModuleDeclaration* src_;
    std::vector<const Identifier*> inputs_;
    std::unordered_map<VId, const Identifier*> state_;
    std::vector<std::pair<const Identifier*, VId>> outputs_;
    std::vector<const SystemTaskEnableStatement*> tasks_;

    // Control State:
    bool there_were_tasks_;
    VarTable<V,A,T> table_;
    std::unordered_map<FId, interfacestream*> streams_;
    std::vector<std::pair<FId, interfacestream*>> stream_cache_;

    // Stream Caching Helpers:
    bool is_constant(const Expression* e) const;

    // Control Helpers:
    interfacestream* get_stream(FId fd);
    bool handle_tasks();

    // Indexes system tasks and inserts the identifiers which appear in those
    // tasks into the variable table.
    class Inserter : public Visitor {
      public:
        explicit Inserter(AvmmLogic* av);
        ~Inserter() override = default;
      private:
        AvmmLogic* av_;
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

    // Synchronizes the locations in the variable table which correspond to the
    // identifiers which appear in an AST subtree. 
    class Sync : public Visitor {
      public:
        explicit Sync(AvmmLogic* av);
        ~Sync() override = default;
      private:
        AvmmLogic* av_;
        void visit(const Identifier* id) override;
    };

    // Evaluation Helpers:
    Evaluate eval_;
    Sync sync_;
    Scanf scanf_;
    Printf printf_;
};

template <size_t V, typename A, typename T>
inline AvmmLogic<V,A,T>::AvmmLogic(Interface* interface, ModuleDeclaration* src, size_t slot) : Logic(interface), sync_(this) { 
  src_ = src;
  cb_ = nullptr;
  slot_ = slot;
  tasks_.push_back(nullptr);
}

template <size_t V, typename A, typename T>
inline AvmmLogic<V,A,T>::~AvmmLogic() {
  if (cb_ != nullptr) {
    cb_();
  }
  delete src_;
  for (auto& s : streams_) {
    delete s.second;
  }
}

template <size_t V, typename A, typename T>
inline AvmmLogic<V,A,T>& AvmmLogic<V,A,T>::set_input(const Identifier* id, VId vid) {
  if (table_.find(id) == table_.end()) {
    table_.insert(id);
  }
  if (inputs_.size() <= vid) {
    inputs_.resize(vid+1, nullptr);
  }
  inputs_[vid] = id;
  return *this;
}

template <size_t V, typename A, typename T>
inline AvmmLogic<V,A,T>& AvmmLogic<V,A,T>::set_state(bool is_volatile, const Identifier* id, VId vid) {
  // NOTE: Volatile variables still need to be placed in the variable table.
  // This is how an AvmmCore keeps track of variables that are sensitive to
  // non-blocking updates.
  if (table_.find(id) == table_.end()) {
    table_.insert(id);
  }   
  if (!is_volatile) {
    state_.insert(std::make_pair(vid, id));
  }
  return *this;
}

template <size_t V, typename A, typename T>
inline AvmmLogic<V,A,T>& AvmmLogic<V,A,T>::set_output(const Identifier* id, VId vid) {
  if (table_.find(id) == table_.end()) { 
    table_.insert(id);
  }
  outputs_.push_back(std::make_pair(id, vid));
  return *this;
}

template <size_t V, typename A, typename T>
inline AvmmLogic<V,A,T>& AvmmLogic<V,A,T>::index_tasks() {
  Inserter i(this);
  src_->accept(&i);
  return *this;
}

template <size_t V, typename A, typename T>
inline AvmmLogic<V,A,T>& AvmmLogic<V,A,T>::set_callback(Callback cb) {
  cb_ = cb;
  return *this;
}

template <size_t V, typename A, typename T>
inline VarTable<V,A,T>* AvmmLogic<V,A,T>::get_table() {
  return &table_;
}

template <size_t V, typename A, typename T>
inline const VarTable<V,A,T>* AvmmLogic<V,A,T>::get_table() const {
  return &table_;
}

template <size_t V, typename A, typename T>
inline State* AvmmLogic<V,A,T>::get_state() {
  auto* s = new State();
  for (const auto& sv : state_) {
    table_.read_var(slot_, sv.second);
    s->insert(sv.first, eval_.get_array_value(sv.second));
  }
  return s;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::set_state(const State* s) {
  table_.write_control_var(table_.reset_index(), 1);
  for (const auto& sv : state_) {
    const auto itr = s->find(sv.first);
    if (itr != s->end()) {
      table_.write_var(slot_, sv.second, itr->second);
    }
  }
  table_.write_control_var(table_.reset_index(), 1);
  table_.write_control_var(table_.resume_index(), 1);
}

template <size_t V, typename A, typename T>
inline Input* AvmmLogic<V,A,T>::get_input() {
  auto* i = new Input();
  for (size_t v = 0, ve = inputs_.size(); v < ve; ++v) {
    const auto* id = inputs_[v];
    if (id == nullptr) {
      continue;
    }
    table_.read_var(slot_, id);
    i->insert(v, eval_.get_value(id));
  }
  return i;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::set_input(const Input* i) {
  table_.write_control_var(table_.reset_index(), 1);
  for (size_t v = 0, ve = inputs_.size(); v < ve; ++v) {
    const auto* id = inputs_[v];
    if (id == nullptr) {
      continue;
    }
    const auto itr = i->find(v);
    if (itr != i->end()) {
      table_.write_var(slot_, id, itr->second);
    }
  }
  table_.write_control_var(table_.reset_index(), 1);
  table_.write_control_var(table_.resume_index(), 1);
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::finalize() {
  // Iterate over tasks. Now that we have the program state in place, we can
  // cache pointers to streams to make system task handling faster. Remember,
  // the task index starts from 1.
  stream_cache_.resize(tasks_.size(), std::make_pair(0, nullptr));
  for (size_t i = 1, ie = tasks_.size(); i < ie; ++i) {
    const auto* t = tasks_[i];
    const Expression* fd = nullptr;
    switch (t->get_tag()) {
      case Node::Tag::get_statement:
        fd = static_cast<const GetStatement*>(t)->get_fd();
        break;
      case Node::Tag::fflush_statement:
        fd = static_cast<const FflushStatement*>(t)->get_fd();
        break;
      case Node::Tag::put_statement: 
        fd = static_cast<const PutStatement*>(t)->get_fd();
        break;
      case Node::Tag::fseek_statement: 
        fd = static_cast<const FseekStatement*>(t)->get_fd();
        break;
      default:
        continue;
    }
    fd->accept(&sync_);
    const auto fd_val = eval_.get_value(fd).to_uint();
    stream_cache_[i] = make_pair(fd_val, get_stream(fd_val));
  }
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::read(VId id, const Bits* b) {
  assert(id < inputs_.size());
  assert(inputs_[id] != nullptr);
  table_.write_var(slot_, inputs_[id], *b);
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::evaluate() {
  there_were_tasks_ = false;
  while (handle_tasks()) {
    table_.write_control_var(table_.resume_index(), 1);
  }
  for (const auto& o : outputs_) {
    table_.read_var(slot_, o.first);
    interface()->write(o.second, &eval_.get_value(o.first));
  }
}

template <size_t V, typename A, typename T>
inline bool AvmmLogic<V,A,T>::there_are_updates() const {
  return table_.read_control_var(table_.there_are_updates_index()) != 0;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::update() {
  table_.write_control_var(table_.apply_update_index(), 1);
  evaluate();
}

template <size_t V, typename A, typename T>
inline bool AvmmLogic<V,A,T>::there_were_tasks() const {
  return there_were_tasks_;
}

template <size_t V, typename A, typename T>
inline size_t AvmmLogic<V,A,T>::open_loop(VId clk, bool val, size_t itr) {
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

template <size_t V, typename A, typename T>
inline const Identifier* AvmmLogic<V,A,T>::open_loop_clock() {
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

template <size_t V, typename A, typename T>
inline bool AvmmLogic<V,A,T>::is_constant(const Expression* e) const {
  // Numbers are constants
  if (e->is(Node::Tag::number)) {
    return true;
  }
  // Anything other than an identifier might not be
  if (!e->is(Node::Tag::identifier)) {
    return false; 
  }

  // Resolve this id 
  const auto* id = static_cast<const Identifier*>(e);
  const auto* r = Resolve().get_resolution(id);
  assert(r != nullptr);
  // Anything other than a reg declaration might not be a constant
  const auto* p = r->get_parent();
  if (!p->is(Node::Tag::reg_declaration)) {
    return false;
  }

  // Anything other than a number or fopen val might not be constant
  const auto* d = static_cast<const RegDeclaration*>(p);
  const auto fo = d->get_val()->is(Node::Tag::fopen_expression);
  const auto n = d->get_val()->is(Node::Tag::number);
  if (!fo && !n) {
    return false;
  }

  // If this fd ever appears on the lhs of an assignment, it might not be a constant
  for (auto i = Resolve().use_begin(r), ie = Resolve().use_end(r); i != ie; ++i) {
    const auto* p = (*i)->get_parent();
    switch (p->get_tag()) {
      case Node::Tag::blocking_assign:
        if (static_cast<const BlockingAssign*>(p)->get_lhs() == *i) {
          return false;
        }
        break;
      case Node::Tag::nonblocking_assign:
        if (static_cast<const NonblockingAssign*>(p)->get_lhs() == *i) {
          return false;
        }
        break;
      case Node::Tag::variable_assign:
        if (static_cast<const VariableAssign*>(p)->get_lhs() == *i) {
          return false;
        }
        break;
      default:
        assert(false);
    }
  }

  // This is definitely a constant
  return true;
}

template <size_t V, typename A, typename T>
inline interfacestream* AvmmLogic<V,A,T>::get_stream(FId fd) {
  const auto itr = streams_.find(fd);
  if (itr != streams_.end()) {
    return itr->second;
  }
  auto* is = new interfacestream(interface(), fd);
  streams_[fd] = is;
  return is;
}

template <size_t V, typename A, typename T>
inline bool AvmmLogic<V,A,T>::handle_tasks() {
  volatile auto task_id = table_.read_control_var(table_.there_were_tasks_index());
  if (task_id == 0) {
    return false;
  }
  assert(task_id != T(-1));
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
      auto is = stream_cache_[task_id];
      if (is.second == nullptr) {
        fs->accept_fd(&sync_);
        is.first = eval_.get_value(fs->get_fd()).to_uint();
        is.second = get_stream(is.first);
      }
      is.second->clear();
      is.second->flush();
      table_.write_control_var(table_.feof_index(), (is.first << 1) | is.second->eof());

      break;
    }
    case Node::Tag::fseek_statement: {
      const auto* fs = static_cast<const FseekStatement*>(task);
      auto is = stream_cache_[task_id];
      if (is.second == nullptr) {
        fs->accept_fd(&sync_);
        is.first = eval_.get_value(fs->get_fd()).to_uint();
        is.second = get_stream(is.first);
      }

      fs->accept_offset(&sync_);
      const auto offset = eval_.get_value(fs->get_offset()).to_uint();
      const auto op = eval_.get_value(fs->get_op()).to_uint();
      const auto way = (op == 0) ? std::ios_base::beg : (op == 1) ? std::ios_base::cur : std::ios_base::end;

      is.second->clear();
      is.second->seekg(offset, way); 
      is.second->seekp(offset, way); 
      table_.write_control_var(table_.feof_index(), (is.first << 1) | is.second->eof());

      break;
    }
    case Node::Tag::get_statement: {
      const auto* gs = static_cast<const GetStatement*>(task);
      auto is = stream_cache_[task_id];
      if (is.second == nullptr) {
        gs->accept_fd(&sync_);
        is.first = eval_.get_value(gs->get_fd()).to_uint();
        is.second = get_stream(is.first);
      }

      scanf_.read_without_update(*is.second, &eval_, gs);
      if (gs->is_non_null_var()) {
        const auto* r = Resolve().get_resolution(gs->get_var());
        assert(r != nullptr);
        table_.write_var(slot_, r, scanf_.get());
      }
      if (is.second->eof()) {
        table_.write_control_var(table_.feof_index(), (is.first << 1) | 1);
      }

      break;
    }  
    case Node::Tag::put_statement: {
      const auto* ps = static_cast<const PutStatement*>(task);
      auto is = stream_cache_[task_id];
      if (is.second == nullptr) {
        ps->accept_fd(&sync_);
        is.first = eval_.get_value(ps->get_fd()).to_uint();
        is.second = get_stream(is.first);
      }

      ps->accept_expr(&sync_);
      printf_.write(*is.second, &eval_, ps);
      if (is.second->eof()) {
        table_.write_control_var(table_.feof_index(), (is.first << 1) | 1);
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

template <size_t V, typename A, typename T>
inline AvmmLogic<V,A,T>::Inserter::Inserter(AvmmLogic* av) : Visitor() {
  av_ = av;
  in_args_ = false;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const Identifier* id) {
  Visitor::visit(id);
  const auto* r = Resolve().get_resolution(id);
  if (in_args_ && (av_->table_.find(r) == av_->table_.end())) {
    av_->table_.insert(r);
  }
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const FeofExpression* fe) {
  // Don't insert this into the task index
  in_args_ = true;
  fe->accept_fd(this);
  in_args_ = false;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const DebugStatement* ds) {
  av_->tasks_.push_back(ds);
  // Don't descend, there aren't any expressions below here
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const FflushStatement* fs) {
  av_->tasks_.push_back(fs);
  in_args_ = true;
  fs->accept_fd(this);
  in_args_ = false;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const FinishStatement* fs) {
  av_->tasks_.push_back(fs);
  in_args_ = true;
  fs->accept_arg(this);
  in_args_ = false;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const FseekStatement* fs) {
  av_->tasks_.push_back(fs);
  in_args_ = true;
  fs->accept_fd(this);
  fs->accept_offset(this);
  in_args_ = false;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const GetStatement* gs) {
  av_->tasks_.push_back(gs);
  in_args_ = true;
  gs->accept_fd(this);
  in_args_ = false;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const PutStatement* ps) {
  av_->tasks_.push_back(ps);
  in_args_ = true;
  ps->accept_fd(this);
  ps->accept_expr(this);
  in_args_ = false;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const RestartStatement* rs) {
  av_->tasks_.push_back(rs);
  in_args_ = true;
  rs->accept_arg(this);
  in_args_ = false;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const RetargetStatement* rs) {
  av_->tasks_.push_back(rs);
  in_args_ = true;
  rs->accept_arg(this);
  in_args_ = false;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const SaveStatement* ss) {
  av_->tasks_.push_back(ss);
  in_args_ = true;
  ss->accept_arg(this);
  in_args_ = false;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Inserter::visit(const YieldStatement* ys) {
  av_->tasks_.push_back(ys);
}

template <size_t V, typename A, typename T>
inline AvmmLogic<V,A,T>::Sync::Sync(AvmmLogic* av) : Visitor() {
  av_ = av;
}

template <size_t V, typename A, typename T>
inline void AvmmLogic<V,A,T>::Sync::visit(const Identifier* id) {
  id->accept_dim(this);
  const auto* r = Resolve().get_resolution(id);
  assert(r != nullptr);
  assert(av_->table_.find(r) != av_->table_.end());
  av_->table_.read_var(av_->slot_, r);
}

} // namespace cascade::avmm

#endif
