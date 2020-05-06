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

#include "include/cascade_slave.h"
#include "target/compiler.h"
#include "target/core/avmm/avalon/avalon_compiler.h"
#include "target/core/avmm/de10/de10_compiler.h"
#include "target/core/aos/amorphos/amorphos_compiler.h"
#include "target/core/aos/f1/f1_compiler.h"
#include "target/core/avmm/ulx3s/ulx3s_compiler.h"
#include "target/core/avmm/verilator/verilator_compiler.h"
#include "target/core/sw/sw_compiler.h"
#include "target/core/proxy/proxy_compiler.h"

using namespace std;

namespace cascade {

CascadeSlave::CascadeSlave() {
  set_listeners("./cascade_sock", 8800);

  remote_compiler_.set("avalon32", new avmm::Avalon32Compiler());
  remote_compiler_.set("de10", new avmm::De10Compiler());
  remote_compiler_.set("amorphos", new aos::AmorphosCompiler());
  remote_compiler_.set("f1", new aos::F1Compiler());
  remote_compiler_.set("proxy", new proxy::ProxyCompiler());
  remote_compiler_.set("sw", new sw::SwCompiler());
  remote_compiler_.set("ulx3s32", new avmm::Ulx3s32Compiler());
  remote_compiler_.set("verilator32", new avmm::Verilator32Compiler());
  #if __x86_64__ || __ppc64__
  remote_compiler_.set("avalon64", new avmm::Avalon64Compiler());
  remote_compiler_.set("verilator64", new avmm::Verilator64Compiler());
  #endif

  set_quartus_server("localhost", 9900);
  set_vivado_server("localhost", 9900, 0);
}

CascadeSlave::~CascadeSlave() {
  stop_now();
}

CascadeSlave& CascadeSlave::set_listeners(const string& path, size_t port) {
  remote_compiler_.set_path(path);
  remote_compiler_.set_port(port);
  return *this;
}

CascadeSlave& CascadeSlave::set_quartus_server(const string& host, size_t port) {
  auto* dc = remote_compiler_.get("de10");
  assert(dc != nullptr);
  static_cast<avmm::De10Compiler*>(dc)->set_host(host);
  static_cast<avmm::De10Compiler*>(dc)->set_port(port);
  return *this;
}

CascadeSlave& CascadeSlave::set_vivado_server(const string& host, size_t port, size_t fpga) {
  auto* fc = remote_compiler_.get("f1");
  assert(fc != nullptr);
  static_cast<aos::F1Compiler*>(fc)->set_host(host);
  static_cast<aos::F1Compiler*>(fc)->set_port(port);
  static_cast<aos::F1Compiler*>(fc)->set_fpga(fpga);
  return *this;
}

CascadeSlave& CascadeSlave::run() {
  remote_compiler_.run();
  return *this;
}

CascadeSlave& CascadeSlave::request_stop() {
  remote_compiler_.request_stop();
  return *this;
}

CascadeSlave& CascadeSlave::wait_for_stop() {
  remote_compiler_.wait_for_stop();
  return *this;
}

CascadeSlave& CascadeSlave::stop_now() {
  remote_compiler_.stop_now();
  return *this;
}

} // namespace cascade
