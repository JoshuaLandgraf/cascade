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

#include "target/core/aos/machinify.h"

#include "verilog/analyze/evaluate.h"
#include "verilog/analyze/resolve.h"
#include "verilog/ast/ast.h"

using namespace std;

namespace cascade::aos {

Machinify::Generate::Generate(size_t idx,
    const std::map<const SystemTaskEnableStatement*,uint16_t>* tm) : Visitor() { 
  idx_ = idx;
  task_map_ = tm;
}

const SeqBlock* Machinify::Generate::text() const {
  return machine_;
}

size_t Machinify::Generate::name() const {
  return idx_;
}

size_t Machinify::Generate::final_state() const {
  return current_.first;
}

void Machinify::Generate::run(const EventControl* ec, const Statement* s) {
  // Create a state machine with a single state
  machine_ = new SeqBlock();
  next_state();

  // Populate the state machine
  s->accept(this);

  // Append a done state. If the last state in the machine is empty, we can use
  // that one. Otherwise, we'll create one last transition to an empty state.
  auto c = current_;
  if (!c.second->empty_stmts()) {
    transition(c.second, c.first+1);
    next_state();
    c = current_;
  }
  c.second->push_back_stmts(new BlockingAssign(new Identifier(new Id("__state"), new Number(Bits(16, idx_))), new Number(Bits(16, final_state()))));

  // Tie everything together into a conditional statement
  auto i = ec->begin_events();
  Expression* guard = to_guard(*i++);
  for (auto ie = ec->end_events(); i != ie; ++i) {
    guard = new BinaryExpression(to_guard(*i), BinaryExpression::Op::PPIPE, guard);
  }
  machine_->push_front_stmts(new BlockingAssign(
    new Identifier(new Id("__state"), new Number(Bits(16, idx_))),
    new ConditionalExpression(
      guard,
      new Number(Bits(false)),
      new Identifier(new Id("__state"), new Number(Bits(16, idx_)))
    )
  ));
  machine_->push_back_stmts(new BlockingAssign(
    new Identifier(new Id("__paused"), new Number(Bits(16, idx_))),
    new ConditionalExpression(
      new Identifier("__reset"),
      new Number(Bits(1, 1)),
      new ConditionalExpression(
        new Identifier("__continue"),
        new Number(Bits(1, 0)),
        new Identifier(new Id("__paused"), new Number(Bits(16, idx_)))
      )
    )
  ));
  machine_->push_back_stmts(new BlockingAssign(
    new Identifier(new Id("__task_id"), new Number(Bits(16, idx_))),
    new ConditionalExpression(
      new Identifier("__reset"),
      new Number(Bits(16, -1)),
      new ConditionalExpression(
        new Identifier("__continue"),
        new Number(Bits(16, 0)),
        new Identifier(new Id("__task_id"), new Number(Bits(16, idx_)))
      )
    )
  ));
  machine_->push_back_stmts(new BlockingAssign(
    new Identifier(new Id("__state"), new Number(Bits(16, idx_))),
    new ConditionalExpression(
      new Identifier("__reset"),
      new Number(Bits(16, final_state())),
      new Identifier(new Id("__state"), new Number(Bits(16, idx_)))
    )
  ));
  
  // In progress
  /*
  machine_->push_front_stmts(
    new BlockingAssign(
      new Identifier(new Id("__paused"), new Number(Bits(16, idx_))),
      new ConditionalExpression(
        new Identifier(new Id("__f_ack"), new Number(Bits(16, idx_))),
        new Number(Bits(1, 0)),
        new Identifier(new Id("__paused"), new Number(Bits(16, idx_)))
      )
    )
  );*/
}

void Machinify::Generate::visit(const BlockingAssign* ba) {
  // Check whether this is a task
  const auto is_task = ba->get_lhs()->eq("__task_id");

  // If it's not, we can append it and move on. Otherwise, we need to record
  // the state that it appears in and mangle it a bit.
  if (!is_task) {
    append(ba);
  } else {
    append(new BlockingAssign(new Identifier(new Id("__paused"), new Number(Bits(16, idx_))), new Number(Bits(1, 1))));
    auto* c = ba->clone();
    c->get_lhs()->push_front_dim(new Number(Bits(16, idx_)));
    append(c);
    delete c;
  }

  // NOTE: We have the invariant that our code doesn't have any nested seq
  // blocks (which we didn't introduce ourselves, and by construction won't
  // have any tasks inside them).  
  
  // If this is the last statement in a seq block, it's already sitting at a
  // state boundary, and there's no need to introduce another break.
  const auto* p = ba->get_parent();
  if (p->is(Node::Tag::seq_block)) {
    const auto* sb = static_cast<const SeqBlock*>(p);
    if (sb->back_stmts() == ba) {
      return;
    }
  }
  // Otherwise, if this is a task, we'll need to break for a state transition.
  if (is_task) {
    transition(current_.first+1);
    next_state();
  }
}

void Machinify::Generate::visit(const NonblockingAssign* na) {
  append(na);
}

void Machinify::Generate::visit(const SeqBlock* sb) {
  sb->accept_stmts(this);
}

void Machinify::Generate::visit(const CaseStatement* cs) {
  // TODO(eschkufz) There are similar optimizations to the ones in
  // ConditionalStatement that can still be made here.

  if (!TaskCheck().run(cs)) {
    append(cs);
    return;
  } 

  const auto begin = current_;

  vector<pair<size_t, SeqBlock*>> begins;
  vector<pair<size_t, SeqBlock*>> ends;
  for (auto i = cs->begin_items(), ie = cs->end_items(); i != ie; ++i) {
    next_state();
    begins.push_back(current_);
    (*i)->accept_stmt(this);
    ends.push_back(current_);
  }

  next_state();

  CaseStatement branch(cs->get_type(), cs->get_cond()->clone());
  size_t idx = 0;
  for (auto i = cs->begin_items(), ie = cs->end_items(); i != ie; ++i) {
    branch.push_back_items(new CaseItem(
      new BlockingAssign(
        new Identifier(new Id("__state"), new Number(Bits(16, idx_))),
        new Number(Bits(16, begins[idx++].first))
      )
    ));
    for (auto j = (*i)->begin_exprs(), je = (*i)->end_exprs(); j != je; ++j) {
      branch.back_items()->push_back_exprs((*j)->clone());
    }
  }
  if (!cs->has_default()) {
    branch.push_back_items(new CaseItem(
      new BlockingAssign(
        new Identifier(new Id("__state"), new Number(Bits(16, idx_))),
        new Number(Bits(16, current_.first))
      )
    ));
  }
  append(begin.second, &branch);
  
  for (auto& e : ends) {
    transition(e.second, current_.first);
  }
}

void Machinify::Generate::visit(const ConditionalStatement* cs) {
  // No need to split a conditional statement that doesn't have any io
  if (!TaskCheck().run(cs)) {
    append(cs);
    return;
  }

  // Check whether this conditional has an empty else branch
  const auto empty_else = 
    cs->get_else()->is(Node::Tag::seq_block) &&
    static_cast<const SeqBlock*>(cs->get_else())->empty_stmts();
  // Check whether this is the last statement in a seq block
  const auto last_stmt = 
    cs->get_parent()->is(Node::Tag::seq_block) &&
    static_cast<const SeqBlock*>(cs->get_parent())->back_stmts() == cs;

  // Record the current state
  const auto begin = current_;

  // We definitely need a new state for the true branch
  next_state();
  const auto then_begin = current_;
  cs->get_then()->accept(this);
  const auto then_end = current_;

  // We only need a new state for the else branch if it's non-empty.
  if (!empty_else) {
    next_state();
  }
  const auto else_begin = current_;
  cs->get_else()->accept(this);
  const auto else_end = current_;

  // And if this ISNT the last statement in a seq block or we have a non-empty
  // else, we need a phi node to join the two. 
  const auto phi_node = !empty_else || !last_stmt;
  if (phi_node) {
    next_state();
  }
  
  // And now we need transitions between the branches. The true branch always
  // goes to tbe beginning of the then state, and the else branch either goes
  // to the beginning of the else state or one past the end of the then state.
  ConditionalStatement branch(
    cs->get_if()->clone(),
    new BlockingAssign(
      new Identifier(new Id("__state"), new Number(Bits(16, idx_))),
      new Number(Bits(16, then_begin.first))
    ),
    new BlockingAssign(
      new Identifier(new Id("__state"), new Number(Bits(16, idx_))),
      new Number(Bits(16, !empty_else ? else_begin.first : (then_end.first + 1)))
    )
  );
  append(begin.second, &branch);

  // If we emitted a phi node, the then branch goes there (to the current state).
  // And if the else branch was non-empty, it goes there as well.
  if (phi_node) {
    transition(then_end.second, current_.first);
    if (!empty_else) {
      transition(else_end.second, current_.first);
    }
  }
}

void Machinify::Generate::visit(const GetStatement* gs) {
  const auto* id = gs->get_var();
  const auto* expr = static_cast<const RangeExpression*>(id->get_dim(0));
  const size_t begin_index = Evaluate().get_value(expr->get_lower()).to_uint();
  const size_t end_index = Evaluate().get_value(expr->get_upper()).to_uint() + 1;
  const size_t num_words = end_index - begin_index;
  const uint16_t task_id = task_map_->find(gs)->second;
  
  for (size_t i = begin_index; i < (end_index+2); ++i) {
    if ((i < (end_index+1)) && (i != (begin_index+1))) {
      append(
        new BlockingAssign(
          new Identifier(
            new Id("__fread_req"),
            new Number(Bits(16, idx_))
          ),
          new Number(Bits(1, 1))
        )
      );
      append(
        new BlockingAssign(
          new Identifier(
            new Id("__paused"),
            new Number(Bits(16, idx_))
          ),
          new Number(Bits(1, 1))
        )
      );
    }
    
    if (i > (begin_index+1)) {
      append(
        new BlockingAssign(
          new Identifier(
            new Id("__var"),
            new Number(Bits(16, i-1))
          ),
          new Identifier(
            new Id("__fread_data"),
            new Number(Bits(16, idx_))
          )
        )
      );
    }
    
    if (i == begin_index) {
      transition(current_.first+1);
      next_state();
    } else if (i == (begin_index+1)) {
      auto* then_block = new SeqBlock();
      auto* else_block = new SeqBlock();
      
      // on success, set feof and transition to data transfer states
      auto* rd16 = new Identifier("__fread_data");
      rd16->push_back_dim(new Number(Bits(16, idx_)));
      rd16->push_back_dim(new Number(Bits(16, 16)));
      then_block->push_back_stmts(
        new BlockingAssign(
          new Identifier(
            new Id("__feof"),
            gs->get_fd()->clone()
          ),
          rd16
        )
      );
      then_block->push_back_stmts(
        new BlockingAssign(
          new Identifier(
            new Id("__fread_req"),
            new Number(Bits(16, idx_))
          ),
          new Number(Bits(1, 1))
        )
      );
      then_block->push_back_stmts(
        new BlockingAssign(
          new Identifier(
            new Id("__paused"),
            new Number(Bits(16, idx_))
          ),
          new Number(Bits(1, 1))
        )
      );
      then_block->push_back_stmts(
        new BlockingAssign(
          new Identifier(
            new Id("__state"),
            new Number(Bits(16, idx_))
          ),
          new Number(Bits(16, current_.first+1))
        )
      );
      
      // on failure, transition to task state
      else_block->push_back_stmts(
        new BlockingAssign(
          new Identifier(
            new Id("__fread_req"),
            new Number(Bits(16, idx_))
          ),
          new Number(Bits(1, 0))
        )
      );
      else_block->push_back_stmts(
        new BlockingAssign(
          new Identifier(
            new Id("__paused"),
            new Number(Bits(16, idx_))
          ),
          new Number(Bits(1, 1))
        )
      );
      else_block->push_back_stmts(
        new BlockingAssign(
          new Identifier(
            new Id("__task_id"),
            new Number(Bits(16, idx_))
          ), 
          new Number(Bits(16, task_id))
        )
      );
      else_block->push_back_stmts(
        new BlockingAssign(
          new Identifier(
            new Id("__state"),
            new Number(Bits(16, idx_))
          ),
          new Number(Bits(16, current_.first-1))
        )
      );
      
      auto* rd15_0 = new Identifier("__fread_data");
      rd15_0->push_back_dim(new Number(Bits(16, idx_)));
      rd15_0->push_back_dim(new RangeExpression(16,0));
      append(
        new ConditionalStatement(
          new BinaryExpression(
            rd15_0,
            BinaryExpression::Op::EEQ,
            new Number(Bits(16, task_id))
          ),
          then_block,
          else_block
        )
      );
      next_state();
    } else {
      append(
        new BlockingAssign(
          new Identifier(
            new Id("__fread_req"),
            new Number(Bits(16, idx_))
          ),
          new Number(Bits(1, (i < end_index ? 1 : 0)))
        )
      );
      
      append(
        new BlockingAssign(
          new Identifier(
            new Id("__state"),
            new Number(Bits(16, idx_))
          ),
          new Number(Bits(16, current_.first+1))
        )
      );
      next_state();
    }
  }
}

void Machinify::Generate::visit(const PutStatement* ps) {
  const auto* expr = ps->get_expr();
  size_t num_words = 0;
  if (expr != nullptr) {
    size_t bits_per_element = Evaluate().get_width(expr);
    num_words = (bits_per_element + 64 - 1) / 64;
  }
  const uint16_t task_id = task_map_->find(ps)->second;
  
  for (size_t i = 0; i < (num_words+1); ++i) {
    append(
      new BlockingAssign(
        new Identifier(
          new Id("__fwrite_req"),
          new Number(Bits(16, idx_))
        ),
        new Number(Bits(1, 1))
      )
    );
    append(
      new BlockingAssign(
        new Identifier(
          new Id("__paused"),
          new Number(Bits(16, idx_))
        ),
        new Number(Bits(1, 1))
      )
    );
    
    if (i == 0) {
      append(
        new BlockingAssign(
          new Identifier(
            new Id("__fwrite_data"),
            new Number(Bits(16, idx_))
          ), 
          new Number(Bits(16, task_id))
        )
      );
    } else {
      append(
        new BlockingAssign(
          new Identifier(
            new Id("__fwrite_data"),
            new Number(Bits(16, idx_))
          ),
          new BinaryExpression(
            expr->clone(),
            BinaryExpression::Op::GGT,
            new Number(Bits(16, 64*(i-1)))
          )
        )
      );
    }
    
    transition(current_.first+1);
    next_state();
  }
  
  append(
    new BlockingAssign(
      new Identifier(
        new Id("__fwrite_req"),
        new Number(Bits(16, idx_))
      ),
      new Number(Bits(1, 0))
    )
  );
}

void Machinify::Generate::append(const Statement* s) {
  append(current_.second, s);
}

void Machinify::Generate::append(SeqBlock* sb, const Statement* s) {
  auto* c = s->clone();
  sb->push_back_stmts(c);
}

void Machinify::Generate::transition(size_t n) {
  transition(current_.second, n);
}

void Machinify::Generate::transition(SeqBlock* sb, size_t n) {
  sb->push_back_stmts(new BlockingAssign(
    new Identifier(new Id("__state"), new Number(Bits(16, 0))),
    new Number(Bits(16, n))
  ));
}

void Machinify::Generate::next_state() {
  auto state = machine_->empty_stmts() ? 0 : (current_.first + 1);
  auto* cs = new ConditionalStatement(
    new BinaryExpression(
      new BinaryExpression(new Identifier(new Id("__state"), new Number(Bits(16, idx_))), BinaryExpression::Op::EEQ, new Number(Bits(16, state))),
      BinaryExpression::Op::AAMP,
      new UnaryExpression(UnaryExpression::Op::BANG, new Identifier(new Id("__paused"), new Number(Bits(16, idx_))))
    ),
    new SeqBlock(),
    new SeqBlock()
  );
  machine_->push_back_stmts(cs);

  current_ = make_pair(machine_->size_stmts()-1, static_cast<SeqBlock*>(cs->get_then()));
}

Identifier* Machinify::Generate::to_guard(const Event* e) const {
  assert(e->get_expr()->is(Node::Tag::identifier));
  const auto* i = static_cast<const Identifier*>(e->get_expr());
  switch (e->get_type()) {
    case Event::Type::NEGEDGE:
      return new Identifier(i->front_ids()->get_readable_sid()+"_negedge");
    case Event::Type::POSEDGE:
      return new Identifier(i->front_ids()->get_readable_sid()+"_posedge");
    default:
      assert(false);
      return nullptr;
  }
}

Machinify::~Machinify() {
  for (auto gen : generators_) {
    delete gen.machine_;
  }
}

void Machinify::run(ModuleDeclaration* md, const std::map<const SystemTaskEnableStatement*,uint16_t>* tm) {
  for (auto i = md->begin_items(); i != md->end_items(); ) {
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
    Generate gen(generators_.size(), tm);
    gen.run(ec, tcs->get_stmt());
    generators_.push_back(gen);
    i = md->purge_items(i);
  }
}

Machinify::const_iterator Machinify::begin() const {
  return generators_.begin();
}

Machinify::const_iterator Machinify::end() const {
  return generators_.end();
}

Machinify::TaskCheck::TaskCheck() : Visitor() { } 

bool Machinify::TaskCheck::run(const Node* n) {
  res_ = false; 
  n->accept(this);
  return res_;
}

void Machinify::TaskCheck::visit(const BlockingAssign* ba) {
  const auto* i = ba->get_lhs();
  if (i->eq("__task_id")) {
    res_ = true;
  }
}

void Machinify::TaskCheck::visit(const GetStatement* gs) {
  res_ = true;
}

void Machinify::TaskCheck::visit(const PutStatement* ps) {
  res_ = true;
}

} // namespace cascade::aos
