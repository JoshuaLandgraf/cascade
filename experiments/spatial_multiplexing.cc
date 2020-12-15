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
  //hypervisor.set_quartus_server("192.168.8.1", 9900);
  hypervisor.run();

  Cascade c1;
  ofstream log1("df.log");
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

  c1 << "`include \"share/cascade/march/regression/remote.v\"\n";
  c1 << "`include \"share/cascade/test/benchmark/df/df_tb_de10.v\"\n";
  c1.flush();

  this_thread::sleep_for(chrono::seconds(20));

  Cascade c2;
  ofstream log2("bitcoin.log");
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

  c2 << "`include \"share/cascade/march/regression/remote.v\"\n";
  c2 << "`include \"share/cascade/test/benchmark/bitcoin/run_30.v\"\n";
  c2.flush();
  
  this_thread::sleep_for(chrono::seconds(20));
  
  Cascade c3;
  ofstream log3("adpcm.log");
  if (log_separately) {
    c3.set_stdout(log3.rdbuf());
    c3.set_stderr(log3.rdbuf());
    c3.set_stdinfo(log3.rdbuf());
  } else {
    c3.set_stdout(cout.rdbuf());
    c3.set_stderr(cout.rdbuf());
    c3.set_stdinfo(cout.rdbuf());
  }
  c3.set_stdout(cout.rdbuf());
  c3.set_stderr(cout.rdbuf());
  c3.set_stdinfo(cout.rdbuf());
  c3.set_profile_interval(1);
  c3.set_fopen_dirs("..");
  c3.run();
  
  c3 << "`include \"share/cascade/march/regression/remote.v\"\n";
  c3 << "`include \"share/cascade/test/benchmark/bitcoin/run_30.v\"\n";
  c3.flush();
  
  this_thread::sleep_for(chrono::seconds(30));
  
  c3.stop_now();
  c2.stop_now();
  c1.stop_now();

  // Let everything go out of scope in reverse of order it was declared in.
  // This avoids a bug which occurs when the hypervisor is torn down first.

  return 0;
}
