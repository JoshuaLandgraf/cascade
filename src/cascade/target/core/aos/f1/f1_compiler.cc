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

#include "target/core/aos/f1/f1_compiler.h"

#include <fcntl.h>
#include <fstream>
#include <sys/mman.h>
#include "common/sockstream.h"
#include "common/system.h"
#include "target/core/aos/f1/vivado_server.h"

using namespace std;

namespace cascade::aos {

F1Compiler::F1Compiler() : AosCompiler<uint64_t>() {
  set_host("localhost"); 
  set_port(9900);
}

F1Compiler::~F1Compiler() {}

F1Compiler& F1Compiler::set_host(const string& host) {
  host_ = host;
  return *this;
}

F1Compiler& F1Compiler::set_port(uint32_t port) {
  port_ = port;
  return *this;
}

F1Compiler& F1Compiler::set_fpga(uint32_t fpga) {
  fpga_ = fpga;
  return *this;
}

F1Logic* F1Compiler::build(Interface* interface, ModuleDeclaration* md, size_t slot) {
  auto* fl = new F1Logic(interface, md, fpga_, slot);
  if (!fl->connected()) {
    if (System::execute(System::src_root() + "/share/cascade/f1/daemon/start.sh >/dev/null 2>&1") != 0) {
    	cerr << "Could not start AOS daemon" << endl;
    	delete fl;
    	return nullptr;
    }
  }

  if (fl->connected()) {
    return fl;
  } else {
    delete fl;
    return nullptr;
  }
}

bool F1Compiler::compile(const string& text, mutex& lock) {
  sockstream sock(host_.c_str(), port_);
  if (sock.error()) {
    std::cerr << "Error: could not connect to compiler" << std::endl;
    return false;
  }

  compile(&sock, text);
  lock.unlock();
  const auto res = block_on_compile(&sock);
  lock.lock();

  if (res) {
    return reprogram(&sock);
  } else {
    return false;
  }
}

void F1Compiler::stop_compile() {
  sockstream sock(host_.c_str(), port_);
  if (sock.error()) {
    std::cerr << "Error: could not connect to compiler" << std::endl;
    return;
  }

  sock.put(static_cast<uint8_t>(VivadoServer::Rpc::KILL_ALL));
  sock.flush();
  sock.get();
}

void F1Compiler::compile(sockstream* sock, const string& text) {
  // Send a compile request. We'll block here until there are no more compile threads
  // running.
  sock->put(static_cast<uint8_t>(VivadoServer::Rpc::COMPILE));
  sock->flush();
  sock->get();

  // Send code to the vivado server, we won't hear back from this socket until
  // compilation is finished or it was aborted.
  sock->write(text.c_str(), text.length());
  sock->put('\0');
  sock->flush();
}

bool F1Compiler::block_on_compile(sockstream* sock) {
  return (static_cast<VivadoServer::Rpc>(sock->get()) == VivadoServer::Rpc::OKAY);
}

bool F1Compiler::reprogram(sockstream* sock) {
  bool res = false;
  get_compiler()->schedule_state_safe_interrupt([this, sock, &res]{
    // We'll receive a string with the AGFI generated by Amazon / the vivado server
    string agfi_str;
    getline(*sock, agfi_str, '\0');
    
    // Check if image already loaded
    string cmd = "grep " + agfi_str + " -q <<< $(sudo fpga-describe-local-image -S";
    cmd += to_string(fpga_) + ")";
    if (false && System::execute(cmd) == 0) {
      cout << "FPGA " << to_string(fpga_) << " already configured with " << agfi_str << endl;
      res = true;
    } else {
      // Trigger local image load
      cout << "Deploying " << agfi_str << " to fpga " << to_string(fpga_) << endl;
      cmd = "sudo fpga-load-local-image -S";
      cmd += to_string(fpga_) + " -I " + agfi_str + " > /dev/null";
      int ret = System::execute(cmd);
      if (ret != 0) {
        cout << "Reprogramming fpga " << to_string(fpga_) << " failed" << endl;
      }
      res = (ret == 0);
    }

    // Send a byte to acknowledge that we're done
    // TODO: delete if unnecessary
    sock->put(0);
    sock->flush();
  });
  return res;
}

} // namespace cascade::aos