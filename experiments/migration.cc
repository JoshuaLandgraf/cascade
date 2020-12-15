#include <chrono>
#include <thread>
#include <fstream>
#include <iostream>
#include "../include/cascade.h"
#include "../include/cascade_slave.h"
#include <unistd.h>

using namespace cascade;
using namespace std;

int main() {
  CascadeSlave hypervisor;
  hypervisor.set_listeners("/tmp/fpga_socket", 8800);
  hypervisor.run();
  
  CascadeSlave hypervisor2;
  hypervisor2.set_listeners("/tmp/fpga_socket2", 8801);
  hypervisor2.run();

  Cascade c1;
  c1.set_stdout(cout.rdbuf());
  c1.set_stderr(cout.rdbuf());
  c1.set_stdinfo(cout.rdbuf());
  c1.set_profile_interval(1);
  c1.set_fopen_dirs("../");
  c1.run();

  c1 << "`include \"share/cascade/march/regression/remote.v\"\n";
  c1 << "`include \"share/cascade/test/benchmark/mips32/run_bubble_128_1024.v\"\n";
  c1.flush();

  this_thread::sleep_for(chrono::seconds(15));

  //chdir(".."); // workaround for bug in retarget
  c1.clear();
  c1 << "initial $retarget(\"regression/remote2\");\n";
  c1.flush();
  
  this_thread::sleep_for(chrono::seconds(15));

  c1.stop_now();

  // Let everything go out of scope in reverse of order it was declared in.
  // This avoids a bug which occurs when the hypervisor is torn down first.

  return 0;
}
