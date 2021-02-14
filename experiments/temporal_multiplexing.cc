#include <chrono>
#include <thread>
#include <fstream>
#include <iostream>
#include "../include/cascade.h"
#include "../include/cascade_slave.h"

using namespace cascade;
using namespace std;

int main() {
  const bool log_separately = false;
  
  CascadeSlave hypervisor;
  hypervisor.set_listeners("/tmp/fpga_socket", 8800);
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
  c1.set_profile_interval(2);
  c1.set_fopen_dirs("..");
  c1.run();

  c1 << "`include \"share/cascade/march/regression/remote.v\"\n";
  c1 << "`include \"share/cascade/test/benchmark/regex/run_disjunct_256.v\"\n";
  c1.flush();

  this_thread::sleep_for(chrono::seconds(50));

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
  c2.set_profile_interval(2);
  c2.set_fopen_dirs("..");
  c2.run();

  c2 << "`include \"share/cascade/march/regression/remote.v\"\n";
  c2 << "`include \"share/cascade/test/benchmark/nw/run_8.v\"\n";
  c2.flush();
  
  this_thread::sleep_for(chrono::seconds(70));
  
  c2.stop_now();
  
  this_thread::sleep_for(chrono::seconds(20));

  c1.stop_now();

  // Let everything go out of scope in reverse of order it was declared in.
  // This avoids a bug which occurs when the hypervisor is torn down first.

  return 0;
}
