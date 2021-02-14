#include <chrono>
#include <thread>
#include "../include/cascade.h"

using namespace cascade;
using namespace std;

int main() {
  Cascade c1;
  c1.set_stdout(cout.rdbuf());
  c1.set_stderr(cout.rdbuf());
  c1.set_stdinfo(cout.rdbuf());
  c1.set_profile_interval(2);
  c1.set_fopen_dirs("..");
  c1.run();

  c1 << "`include \"share/cascade/march/regression/minimal.v\"\n";
  c1 << "`include \"share/cascade/test/benchmark/bitcoin/run_15.v\"\n";
  c1.flush();

  this_thread::sleep_for(chrono::seconds(40));

  c1.clear();
  c1 << "initial $save(\"state.dat\");\n";
  c1.flush();
  
  this_thread::sleep_for(chrono::seconds(20));

  c1.stop_now();
  return 0;
}
