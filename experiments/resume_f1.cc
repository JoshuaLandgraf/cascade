#include <chrono>
#include <thread>
#include "../include/cascade.h"
#include "target/core/aos/f1/vivado_server.h"

using namespace cascade;
using namespace std;

int main(int argc, char *argv[]) {
  const bool wait_for_stop = false;

  const bool run_vs = (argc == 1);
  aos::VivadoServer* vs1 = nullptr;
  if (run_vs) {
    vs1 = new aos::VivadoServer();
    vs1->set_port(9902);
    assert(!vs1->error());
    vs1->run();
  }

  Cascade c1;
  c1.set_stdout(cout.rdbuf());
  c1.set_stderr(cout.rdbuf());
  c1.set_stdinfo(cout.rdbuf());
  c1.set_profile_interval(2);
  c1.set_fopen_dirs("..");
  c1.set_vivado_server("localhost", 9902, 0);
  c1.run();

  c1 << "`include \"share/cascade/march/regression/f1_minimal.v\"\n";
  c1 << "`include \"share/cascade/test/benchmark/bitcoin/run_30.v\"\n";
  c1.flush();
  
  this_thread::sleep_for(chrono::seconds(21));
  
  c1.clear();
  c1 << "initial $restart(\"state.dat\");\n";
  c1.flush();

  if (wait_for_stop) {
    c1.wait_for_stop();
  } else {
    this_thread::sleep_for(chrono::seconds(50));
    c1.stop_now();
  }
  if (run_vs) vs1->stop_now();

  return 0;
}
