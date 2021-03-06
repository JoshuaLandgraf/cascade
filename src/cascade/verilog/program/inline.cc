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

#include "verilog/program/inline.h"

#include <cassert>
#include <map>
#include <string>
#include <vector>
#include "verilog/analyze/evaluate.h"
#include "verilog/analyze/navigate.h"
#include "verilog/analyze/resolve.h"
#include "verilog/ast/ast.h"
#include "verilog/program/elaborate.h"

using namespace std;

namespace cascade {

Inline::Inline() : Editor() { }

void Inline::inline_source(ModuleDeclaration* md) {
  inline_ = true;
  info_ = new ModuleInfo(md);
  md->accept(this);
  info_->invalidate();
  delete info_;
}

void Inline::outline_source(ModuleDeclaration* md) {
  inline_ = false;
  md->accept(this);
  ModuleInfo(md).invalidate();
}

bool Inline::can_inline(const ModuleDeclaration* md) const {
  const auto* std = md->get_attrs()->get<String>("__std");
  const auto* no_inline = md->get_attrs()->get<String>("__no_inline");
  return (std != nullptr) && std->eq("logic") && (no_inline == nullptr);
}

bool Inline::is_inlined(const ModuleInstantiation* mi) {
  return mi->inline_ != nullptr;
}

const IfGenerateConstruct* Inline::get_source(const ModuleInstantiation* mi) {
  assert(mi->inline_ != nullptr);
  return mi->inline_; 
}

Inline::Qualify::Qualify() : Builder() { }

Expression* Inline::Qualify::qualify_exp(const Expression* e) {
  return e->accept(this);
}

Identifier* Inline::Qualify::qualify_id(const Identifier* id) {
  return id->accept(this);
}

Expression* Inline::Qualify::build(const Identifier* id) {
  const auto* r = Resolve().get_resolution(id);
  assert(r != nullptr);

  auto* res = Resolve().get_full_id(r);
  res->purge_dim();
  id->accept_dim(this, res->back_inserter_dim());

  return res;
}

void Inline::edit(CaseGenerateConstruct* cgc) {
  if (Elaborate().is_elaborated(cgc)) {
    Elaborate().get_elaboration(cgc)->accept(this);
  }
}

void Inline::edit(IfGenerateConstruct* igc) {
  if (Elaborate().is_elaborated(igc)) {
    Elaborate().get_elaboration(igc)->accept(this);
  }
}

void Inline::edit(LoopGenerateConstruct* lgc) {
  if (Elaborate().is_elaborated(lgc)) {
    for (auto* b : Elaborate().get_elaboration(lgc)) {
      b->accept(this);
    }
  }
}

void Inline::edit(ModuleInstantiation* mi) {
  if (inline_) {
    inline_source(mi);
  } else {
    outline_source(mi);
  }
  // Don't descend! We only want to inline THIS module!
}

void Inline::inline_source(ModuleInstantiation* mi) {
  // Nothing to do for code which has already been inlined
  if (is_inlined(mi)) {
    return;
  }
  // Nothing to do for code that we don't support inlining
  assert(Elaborate().is_elaborated(mi));
  auto* src = Elaborate().get_elaboration(mi);
  if (!can_inline(src)) {
    return;
  }

  // Generate connections for this instantiation. We need to do this now before
  // we start modifying the instantiation. Calling ModuleInfo later might
  // result in a refresh against undefined state. But first sort connections
  // lexicographically by name. This is important for guaranteeing
  // deterministic code generation in isolation.
  const auto itr = info_->connections().find(mi->get_iid());
  assert(itr != info_->connections().end());
  map<string, pair<const Identifier*, const Expression*>> sorted_conns;
  for (auto& c : itr->second) {
    sorted_conns.insert(make_pair(Resolve().get_readable_full_id(c.first), c));
  }
  vector<ModuleItem*> conns;
  for (const auto& sc : sorted_conns) {
    const auto& c = sc.second;
    auto* lhs = ModuleInfo(src).is_input(c.first) ? 
      Qualify().qualify_id(c.first) : 
      Qualify().qualify_id(static_cast<const Identifier*>(c.second));
    auto* rhs = ModuleInfo(src).is_input(c.first) ? 
      Qualify().qualify_exp(c.second) : 
      Qualify().qualify_exp(c.first);
    conns.push_back(new ContinuousAssign(lhs, rhs));
  }
  // Move the contents of the instantiation into new inlined code. Downgrade
  // ports to regular declarations and parameters to localparams.
  vector<ModuleItem*> inline_src;
  while (!src->empty_items()) {
    auto* item = src->remove_front_items();
    if (item->is(Node::Tag::port_declaration)) {
      auto* pd = static_cast<PortDeclaration*>(item);
      auto* d = pd->get_decl()->clone();
      switch (pd->get_type()) {
        case PortDeclaration::Type::INPUT:
          d->get_attrs()->set_or_replace("__inline", new String("input"));
          break;
        case PortDeclaration::Type::OUTPUT:
          d->get_attrs()->set_or_replace("__inline", new String("output"));
          break;
        default:
          d->get_attrs()->set_or_replace("__inline", new String("inout"));
          break;
      }
      d->swap_id(pd->get_decl());
      inline_src.push_back(d);
      delete pd;
    } else if (item->is(Node::Tag::parameter_declaration)) {
      auto* pad = static_cast<ParameterDeclaration*>(item);
      auto* ld = new LocalparamDeclaration(
        new Attributes(),
        pad->clone_id(),
        pad->get_type(),
        pad->clone_dim(),
        pad->clone_val()
      );
      ld->get_attrs()->set_or_replace("__inline", new String("parameter"));
      ld->swap_id(pad);
      ld->swap_val(pad);
      inline_src.push_back(ld);
      delete pad;
    } else {
      inline_src.push_back(item);
    }
  }
  // Record the number of items in the new source
  auto* attrs = new Attributes(new AttrSpec(
    new Identifier("__inline"),
    new Number(Bits(32, inline_src.size()))
  ));
  // Finally, append the connections to the new source
  inline_src.insert(inline_src.end(), conns.begin(), conns.end());

  // Update inline decorations
  auto* igc = new IfGenerateConstruct(
    attrs,
    new IfGenerateClause(
      new Number(Bits(true)),
      new GenerateBlock(
        mi->get_iid()->clone(),
        true,
        inline_src.begin(),
        inline_src.end()
      )
    ),
    nullptr
  );
  mi->inline_ = igc;
  igc->parent_ = mi;
  mi->inline_->gen_ = mi->inline_->front_clauses()->get_then();

  // This module is now in an inconsistent state. Invalidate its module info
  // and invalidate the scope that contains the newly inlined code.
  ModuleInfo(src).invalidate();
  Navigate(mi).invalidate();
}

void Inline::outline_source(ModuleInstantiation* mi) {
  // TODO(eschkufz) It's been a long time since this method was actually used. I'm adding
  // an assertion here to flag the fact that it's almost certainly bit-rotted. If and when
  // it goes back into production, we can remove this.
  assert(false);

  // Nothing to do for code which has already been outlined
  if (!is_inlined(mi)) {
    return;
  }
  // Make sure that somehow we aren't outlining something we shouldn't have inlined
  assert(Elaborate().is_elaborated(mi));
  auto* src = Elaborate().get_elaboration(mi);
  assert(can_inline(src));

  // Move this inlined code back into the instantiation. Replace port and
  // parameter delcarations, and delete the connections.
  const auto length = Evaluate().get_value(mi->inline_->get_attrs()->get<Number>("__inline")).to_uint();
  for (size_t i = 0; i < length; ++i) {
    auto* item = mi->inline_->front_clauses()->get_then()->remove_front_items();
    if (item->is(Node::Tag::localparam_declaration)) {
      auto* ld = static_cast<LocalparamDeclaration*>(item);
      if (ld->get_attrs()->get<String>("__inline") != nullptr) {
        auto* pd = new ParameterDeclaration(
          new Attributes(),
          ld->get_id()->clone(),
          ld->get_type(),
          ld->clone_dim(),
          ld->get_val()->clone()
        );
        pd->swap_id(ld);
        src->push_back_items(pd);
        delete ld;
        continue;
      } 
    } else if (item->is_subclass_of(Node::Tag::declaration)) {
      auto* d = static_cast<Declaration*>(item);
      auto* annot = d->get_attrs()->get<String>("__inline");
      if (annot != nullptr && !annot->eq("parameter")) {
        auto* pd = new PortDeclaration(
          new Attributes(),
          annot->eq("input") ? PortDeclaration::Type::INPUT : annot->eq("output") ? PortDeclaration::Type::OUTPUT : PortDeclaration::Type::INOUT,
          d->clone()
        );
        pd->get_decl()->replace_attrs(new Attributes());
        pd->get_decl()->swap_id(d);
        src->push_back_items(pd);
        delete d;
        continue;
      }
    } 
    src->push_back_items(item);
  }
  // Remove what's left of the inlined code and revert decorations
  delete mi->inline_;
  mi->inline_ = nullptr;

  // This module is now back in a consistent state. Invalidate its module info
  // and invalidate the scope that used to contain the inlined code.
  ModuleInfo(src).invalidate();
  Navigate(mi).invalidate();
}

} // namespace cascade
