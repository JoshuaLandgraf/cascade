#include <chrono>
#include <thread>
#include <fstream>
#include <iostream>
#include "../include/cascade.h"
#include "../include/cascade_slave.h"
#include "target/core/aos/f1/vivado_server.h"

using namespace cascade;
using namespace std;

int main(int argc, char *argv[]) {
  const bool run_vs = (argc == 1);
  aos::VivadoServer* vs1 = nullptr;
  aos::VivadoServer* vs2 = nullptr;
  if (run_vs) {
    vs1 = new aos::VivadoServer();
    vs2 = new aos::VivadoServer();
    vs1->set_port(9904);
    vs2->set_port(9900);
    assert(!vs1->error());
    assert(!vs2->error());
    vs1->run();
    vs2->run();
  }

  CascadeSlave hypervisor;
  hypervisor.set_listeners("/tmp/fpga_socket", 8800);
  hypervisor.set_vivado_server("localhost", 9904, 0);
  hypervisor.run();
  
  CascadeSlave hypervisor2;
  hypervisor2.set_listeners("/tmp/fpga_socket2", 8801);
  hypervisor2.set_vivado_server("localhost", 9900, 1);
  hypervisor2.run();

  Cascade c1;
  c1.set_stdout(cout.rdbuf());
  c1.set_stderr(cout.rdbuf());
  c1.set_stdinfo(cout.rdbuf());
  c1.set_profile_interval(1);
  c1.set_fopen_dirs("../");
  c1.run();

  c1 << "`include \"share/cascade/march/regression/f1_remote.v\"\n";
  c1 << "`include \"share/cascade/test/benchmark/mips32/run_bubble_128_32768.v\"\n";
  c1.flush();

  this_thread::sleep_for(chrono::seconds(25));

  c1.clear();
  c1 << "initial $retarget(\"regression/f1_remote2\");\n";
  c1.flush();
  
  this_thread::sleep_for(chrono::seconds(25));

  c1.stop_now();

  if (run_vs) {
    vs1->stop_now();
    vs2->stop_now();
  }

  // Let everything go out of scope in reverse of order it was declared in.
  // This avoids a bug which occurs when the hypervisor is torn down first.

  return 0;
}
