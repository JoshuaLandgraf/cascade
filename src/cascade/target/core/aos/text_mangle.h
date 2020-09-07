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

#ifndef CASCADE_SRC_TARGET_CORE_AOS_TEXT_MANGLE_H
#define CASCADE_SRC_TARGET_CORE_AOS_TEXT_MANGLE_H

#include <stddef.h>
#include <vector>
#include <map>
#include "target/core/aos/var_table.h"
#include "verilog/analyze/module_info.h"
#include "verilog/ast/ast.h"
#include "verilog/ast/visitors/builder.h"
#include "verilog/build/ast_builder.h"

namespace cascade {

namespace aos {

// Pass 1: 
// 
// This pass performs several major text transformations:
// 1. Declarations are deleted.
// 2. Attribute annotations are deleted.
// 3. $feof() expressions are replaced their corresponding vtable entry
// 4. System tasks are transformed into state udpate operations
// 5. Non-blocking assignments are transformed into state update operations

template <typename T>
class TextMangle : public Builder {
  public:
    TextMangle(const ModuleDeclaration* md, const VarTable<T>* vt);
    ~TextMangle() override = default;
    const std::map<const SystemTaskEnableStatement*,uint16_t>* get_task_map();

  private:
    const ModuleDeclaration* md_;
    const VarTable<T>* vt_;
    size_t task_index_;
    std::map<const SystemTaskEnableStatement*,uint16_t> task_map_;

    Attributes* build(const Attributes* as) override;
    ModuleItem* build(const RegDeclaration* rd) override;
    ModuleItem* build(const PortDeclaration* pd) override;
    Expression* build(const FeofExpression* fe) override;
    Statement* build(const BlockingAssign* ba) override;
    Statement* build(const NonblockingAssign* na) override;
    Statement* build(const DebugStatement* ds) override;
    Statement* build(const FflushStatement* fs) override;
    Statement* build(const FinishStatement* fs) override;
    Statement* build(const FseekStatement* fs) override;
    Statement* build(const GetStatement* gs) override;
    Statement* build(const PutStatement* ps) override;
    Statement* build(const RestartStatement* rs) override;
    Statement* build(const RetargetStatement* rs) override;
    Statement* build(const SaveStatement* ss) override;
    Statement* build(const YieldStatement* ys) override;

    Statement* build_task();
    RangeExpression* get_table_range(const Identifier* r, const Identifier* i);
};

using StmtBuilder = AstBuilder<Statement>;

template <typename T>
inline TextMangle<T>::TextMangle(const ModuleDeclaration* md, const VarTable<T>* vt) : Builder() {
  md_ = md;
  vt_ = vt;
  task_index_ = 1;
}

template <typename T>
inline Attributes* TextMangle<T>::build(const Attributes* as) {
  (void) as;
  return new Attributes();
}

template <typename T>
inline ModuleItem* TextMangle<T>::build(const RegDeclaration* rd) {
  return ModuleInfo(md_).is_stateful(rd->get_id()) ? 
    nullptr : 
    new RegDeclaration(
      new Attributes(),
      rd->accept_id(this),
      rd->get_type(),
      rd->accept_dim(this),
      rd->accept_val(this)
    );
}

template <typename T>
inline ModuleItem* TextMangle<T>::build(const PortDeclaration* pd) {
  ModuleInfo info(md_);
  if (info.is_stateful(pd->get_decl()->get_id()) || info.is_input(pd->get_decl()->get_id())) {
    return nullptr;
  } else {
    return new PortDeclaration(new Attributes(), pd->get_type(), pd->accept_decl(this));
  }
}

template <typename T>
inline Expression* TextMangle<T>::build(const FeofExpression* fe) {
  return new Identifier(new Id("__feof"), fe->clone_fd());
}

template <typename T>
inline Statement* TextMangle<T>::build(const BlockingAssign* ba) {
  // Look up the target of this assignment 
  const auto* r = Resolve().get_resolution(ba->get_lhs());
  assert(r != nullptr);

  // If this entry doesn't appear in the vtable, we can leave it as is
  const auto titr = vt_->find(r);
  if (titr == vt_->end()) {
    return ba->clone();
  }
  // Otherwise, replace the original assignment with an assignment to a concatenation
  std::vector<Identifier*> lhs;
  for (size_t i = 0, ie = titr->second.words_per_element; i < ie; ++i) {
    lhs.push_back(new Identifier(new Id("__var"), new Number(Bits(64, titr->second.begin+ie-i-1))));
  }
  return new BlockingAssign(lhs.begin(), lhs.end(), ba->get_rhs()->clone());
}

template <typename T>
inline Statement* TextMangle<T>::build(const NonblockingAssign* na) {
  auto* res = new SeqBlock();

  // Look up the target of this assignment 
  const auto* lhs = na->get_lhs();
  const auto* r = Resolve().get_resolution(lhs);
  assert(r != nullptr);
  
  // Replace the original assignment with an assignment to a temporary variable
  auto* next = lhs->clone();
  next->purge_ids();
  next->push_back_ids(new Id(lhs->front_ids()->get_readable_sid() + "_next"));
  res->push_back_stmts(new BlockingAssign(
    na->clone_ctrl(),
    next,
    na->get_rhs()->clone()
  ));

  // Insert a new assignment to the next mask
  auto* re = get_table_range(r,lhs);
  //const size_t begin_index = Evaluate().get_value(re->get_lower()).to_uint();
  //const size_t end_index   = Evaluate().get_value(re->get_upper()).to_uint() + 1;
  res->push_back_stmts(new BlockingAssign(
    new Identifier(
      new Id("__update_queue"),
      re
    ),
    new UnaryExpression(
      UnaryExpression::Op::TILDE,
      //new Number(Bits(end_index-begin_index, 0))
      new Number(Bits(1, 0))
    )
  ));
  res->push_back_stmts(new NonblockingAssign(
    new Identifier("__there_are_updates"),
	new Number(Bits(1, 1))
  ));

  return res;
}

template <typename T>
inline Statement* TextMangle<T>::build_task() {
  size_t task_id = task_index_++;
  auto sb = new SeqBlock();
  
  auto then_sb = new SeqBlock();
  then_sb->push_back_stmts(
    new BlockingAssign(
      new Identifier("__there_were_tasks"),
      new Number(Bits(1, 1))
    )
  );
  then_sb->push_back_stmts(
    new BlockingAssign(
      new Identifier("__task_id"),
      new Number(Bits(16, task_id))
    )
  );
  then_sb->push_back_stmts(
    new ConditionalStatement(
      new Identifier("__continue"),
      new NonblockingAssign(
        new Identifier(
          new Id("__task_mask"),
          new Number(Bits(16, task_id))
        ),
        new Number(Bits(1, 1))
      ),
      new SeqBlock()
    )
  );
  
  sb->push_back_stmts(
    new ConditionalStatement(
      new BinaryExpression(
        new UnaryExpression(
          UnaryExpression::Op::BANG,
          new Identifier("__there_were_tasks")
        ),
        BinaryExpression::Op::AAMP,
        new UnaryExpression(
          UnaryExpression::Op::BANG,
          new Identifier(
            new Id("__task_mask"),
            new Number(Bits(16, task_id))
          )
        )
      ),
      then_sb,
      new SeqBlock()
    )
  );
  
  return sb;
}

template <typename T>
inline Statement* TextMangle<T>::build(const DebugStatement* ds) {
  return build_task();
}

template <typename T>
inline Statement* TextMangle<T>::build(const FflushStatement* fs) {
  return build_task();
}

template <typename T>
inline Statement* TextMangle<T>::build(const FinishStatement* fs) {
  return build_task();
}

template <typename T>
inline Statement* TextMangle<T>::build(const FseekStatement* fs) {
  return build_task();
}

template <typename T>
inline Statement* TextMangle<T>::build(const GetStatement* gs) {
  return build_task();
  
  // In progress
  const auto* id = gs->get_var();
  const auto* r = Resolve().get_resolution(id);
  size_t begin_index = vt_->index(r);
  size_t bits_per_element = std::max(Evaluate().get_width(r), Evaluate().get_width(id));
  size_t words_per_element = (bits_per_element + (8*sizeof(T)) - 1) / (8*sizeof(T));
  size_t end_index = begin_index + words_per_element;
  
  SystemTaskEnableStatement *st = new GetStatement(
    gs->get_fd()->clone(),
    gs->get_fmt()->clone(),
    new Identifier(
      new Id("__var"),
      new RangeExpression(end_index, begin_index)
    )
  );
  
  task_map_[st] = task_index_++;
  return st;
}

template <typename T>
inline Statement* TextMangle<T>::build(const PutStatement* ps) {
  return build_task();
  
  // In progress
  SystemTaskEnableStatement *st = ps->clone();
  task_map_[st] = task_index_++;
  return st;
}

template <typename T>
inline Statement* TextMangle<T>::build(const RestartStatement* rs) {
  return build_task();
}

template <typename T>
inline Statement* TextMangle<T>::build(const RetargetStatement* rs) {
  return build_task();
}

template <typename T>
inline Statement* TextMangle<T>::build(const SaveStatement* ss) {
  return build_task();
}

template <typename T>
inline Statement* TextMangle<T>::build(const YieldStatement* ys) {
  return build_task();
}

template <typename T>
inline RangeExpression* TextMangle<T>::get_table_range(const Identifier* r, const Identifier* i) {
  // Look up r in the variable table
  const auto titr = vt_->find(r);
  assert(titr != vt_->end());

  // Start with an expression for where this variable begins in the variable table
  Expression* idx = new Number(Bits(64, titr->second.begin));

  // Now iterate over the arity of r and compute a symbolic expression 
  auto mul = titr->second.elements;
  auto iitr = i->begin_dim();
  for (auto a : Evaluate().get_arity(titr->first)) {
    mul /= a;
    idx = new BinaryExpression(
      idx,
      BinaryExpression::Op::PLUS,
      new BinaryExpression(
        (*iitr++)->clone(),
        BinaryExpression::Op::TIMES,
        new Number(Bits(64, mul*titr->second.words_per_element))
      )
    );
  }
  return new RangeExpression(idx, RangeExpression::Type::PLUS, new Number(Bits(64, titr->second.words_per_element)));
}

template <typename T>
const std::map<const SystemTaskEnableStatement*,uint16_t>* TextMangle<T>::get_task_map() {
  return &task_map_;
}

} // namespace aos

} // namespace cascade

#endif
