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
  const bool log_separately = false;

  const bool run_vs = (argc == 1);
  aos::VivadoServer* vs1 = nullptr;
  if (run_vs) {
    vs1 = new aos::VivadoServer();
    vs1->set_port(9907);
    assert(!vs1->error());
    vs1->run();
  }

  CascadeSlave hypervisor;
  hypervisor.set_listeners("/tmp/fpga_socket", 8807);
  hypervisor.set_vivado_server("localhost", 9907, 0);
  hypervisor.run();

  Cascade c1;
  ofstream log1("regex.log");
  if (log_separately) {
    c1.set_stdout(log1.rdbuf());
    c1.set_stderr(log1.rdbuf());
    c1.set_stdinfo(log1.rdbuf());
  } else {
    c1.set_stdout(cout.rdbuf());
    c1.set_stderr(cout.rdbuf());
    c1.set_stdinfo(cout.rdbuf());
  }
  c1.set_profile_interval(1);
  c1.set_fopen_dirs("..");
  c1.run();

  c1 << "`include \"share/cascade/march/regression/f1_remote.v\"\n";
  c1 << "`include \"share/cascade/test/benchmark/regex/run_disjunct_64.v\"\n";
  c1.flush();

  this_thread::sleep_for(chrono::seconds(20));

  Cascade c2;
  ofstream log2("nw.log");
  if (log_separately) {
    c2.set_stdout(log2.rdbuf());
    c2.set_stderr(log2.rdbuf());
    c2.set_stdinfo(log2.rdbuf());
  } else {
    c2.set_stdout(cout.rdbuf());
    c2.set_stderr(cout.rdbuf());
    c2.set_stdinfo(cout.rdbuf());
  }
  c2.set_stdout(cout.rdbuf());
  c2.set_stderr(cout.rdbuf());
  c2.set_stdinfo(cout.rdbuf());
  c2.set_profile_interval(1);
  c2.set_fopen_dirs("..");
  c2.run();

  c2 << "`include \"share/cascade/march/regression/f1_remote.v\"\n";
  c2 << "`include \"share/cascade/test/benchmark/nw/run_8.v\"\n";
  c2.flush();
  
  this_thread::sleep_for(chrono::seconds(30));
  
  c2.stop_now();
  
  this_thread::sleep_for(chrono::seconds(10));

  c1.stop_now();
  if (run_vs) vs1->stop_now();

  // Let everything go out of scope in reverse of order it was declared in.
  // This avoids a bug which occurs when the hypervisor is torn down first.

  return 0;
}
