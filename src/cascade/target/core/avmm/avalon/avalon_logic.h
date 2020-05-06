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

#ifndef CASCADE_SRC_TARGET_CORE_AVMM_AVALON_AVALON_LOGIC_H
#define CASCADE_SRC_TARGET_CORE_AVMM_AVALON_AVALON_LOGIC_H

#include "target/core/common/syncbuf.h"
#include "target/core/avmm/avalon/avalon_logic.h"
#include "target/core/avmm/avmm_logic.h"

namespace cascade::avmm {

template <size_t V, typename A, typename T>
class AvalonLogic : public AvmmLogic<V,A,T> {
  public:
    AvalonLogic(Interface* interface, ModuleDeclaration* md, size_t slot, syncbuf* reqs, syncbuf* resps);
    virtual ~AvalonLogic() override = default;
};

template <size_t V, typename A, typename T>
inline AvalonLogic<V,A,T>::AvalonLogic(Interface* interface, ModuleDeclaration* md, size_t slot, syncbuf* reqs, syncbuf* resps) : AvmmLogic<V,A,T>(interface, md, slot) {
  if constexpr (std::is_same<T, uint32_t>::value) {
    AvmmLogic<V,A,T>::get_table()->set_read([slot, reqs, resps](A index) {
      uint8_t bytes[8];
      bytes[0] = 2;
      *reinterpret_cast<A*>(&bytes[1]) = index;
      reqs->sputn(reinterpret_cast<const char*>(bytes), 3);
      resps->waitforn(reinterpret_cast<char*>(bytes), 4);
      return *reinterpret_cast<T*>(bytes);
    });
    AvmmLogic<V,A,T>::get_table()->set_write([slot, reqs](A index, T val) {
      uint8_t bytes[8];
      bytes[0] = 1;
      *reinterpret_cast<A*>(&bytes[1]) = index;
      *reinterpret_cast<T*>(&bytes[3]) = val;;
      reqs->sputn(reinterpret_cast<const char*>(bytes), 7);
    });
  } else if constexpr (std::is_same<T, uint64_t>::value) {
    AvmmLogic<V,A,T>::get_table()->set_read([slot, reqs, resps](A index) {
      uint8_t bytes[16];
      bytes[0] = 2;
      *reinterpret_cast<A*>(&bytes[1]) = index;
      reqs->sputn(reinterpret_cast<const char*>(bytes), 5);
      resps->waitforn(reinterpret_cast<char*>(bytes), 8);
      return *reinterpret_cast<T*>(bytes);
    });
    AvmmLogic<V,A,T>::get_table()->set_write([slot, reqs](A index, T val) {
      uint8_t bytes[16];
      bytes[0] = 1;
      *reinterpret_cast<A*>(&bytes[1]) = index;
      *reinterpret_cast<T*>(&bytes[5]) = val;;
      reqs->sputn(reinterpret_cast<const char*>(bytes), 13);
    });
  }
}

} // namespace cascade::avmm

#endif
