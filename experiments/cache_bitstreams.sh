#!/bin/bash

NUM_CPU=$(nproc)
if [ "$NUM_CPU" -lt "16" ]; then
  echo "WARNING: an f1.2xlarge instance may not have enough memory"
  echo "Please switch to an f1.4xlarge or f1.16xlarge instance"
  exit 1
fi

OLD_PWD=$PWD
cd ..
if [[ -d ./build ]]; then
  echo "Starting builds..."
  sleep 5
else
  echo "Error: cannot find build directory"
  echo "Please run this script from the experiments directory"
  cd $OLD_PWD
  exit 1
fi

# adpcm
nohup ./build/tools/vivado_server --port 9901 >experiments/9901.log 2>&1 &
sleep 1
./build/tools/cascade --march regression/f1_minimal -e share/cascade/test/benchmark/adpcm/adpcm_6M.v --compiler_port 9901 >/dev/null 2>&1 &
PID1=$!
sleep 10
kill -9 $PID1

# bitcoin (suspend and resume)
nohup ./build/tools/vivado_server --port 9902 >experiments/9902.log 2>&1 &
sleep 1
./build/tools/cascade --march regression/f1_minimal -e share/cascade/test/benchmark/bitcoin/run_30.v --compiler_port 9902 >/dev/null 2>&1 &
PID2=$!
sleep 10
kill -9	$PID2

# df (spatial multiplexing, stage 1)
nohup ./build/tools/vivado_server --port 9903 >experiments/9903.log 2>&1 &
sleep 1
./build/tools/cascade --march regression/f1_minimal -e share/cascade/test/benchmark/df/df_tb_de10.v --compiler_port 9903 >/dev/null 2>&1 &
PID3=$!
sleep 10
kill -9 $PID3

# mips32 (live migration)
nohup ./build/tools/vivado_server --port 9904 >experiments/9904.log 2>&1 &
sleep 1 
./build/tools/cascade --march regression/f1_minimal -e share/cascade/test/benchmark/mips32/run_bubble_128_32768.v --compiler_port 9904 >/dev/null 2>&1 &
PID4=$!
sleep 10
kill -9 $PID4

# nw
nohup ./build/tools/vivado_server --port 9905 >experiments/9905.log 2>&1 &
sleep 1
./build/tools/cascade --march regression/f1_minimal -e share/cascade/test/benchmark/nw/run_8.v --compiler_port 9905 >/dev/null 2>&1 &
PID5=$!
sleep 10
kill -9 $PID5

# regex (temporal multiplexing, stage 1)
nohup ./build/tools/vivado_server --port 9906 >experiments/9906.log 2>&1 &
sleep 1
./build/tools/cascade --march regression/f1_minimal -e share/cascade/test/benchmark/regex/run_disjunct_64.v --compiler_port 9906 >/dev/null 2>&1 &
PID6=$!
sleep 10
kill -9 $PID6

# temporal multiplexing, stage 2
nohup ./build/tools/vivado_server --port 9907 >experiments/9907.log 2>&1 &
sleep 1
./build/tools/cascade_slave --compiler_port 9907 >/dev/null 2>&1 &
PID7=$!
sleep 1
./build/tools/cascade --march regression/f1_remote -e share/cascade/test/benchmark/regex/run_disjunct_64.v >/dev/null 2>&1 &
PID8=$!
sleep 10
./build/tools/cascade --march regression/f1_remote -e share/cascade/test/benchmark/nw/run_8.v >/dev/null 2>&1 &
PID9=$!
sleep 20
kill -9 $PID9
kill -9 $PID8
kill -9 $PID7

# spatial multiplexing, stage 2
nohup ./build/tools/vivado_server --port 9908 >experiments/9908.log 2>&1 &
sleep 1
./build/tools/cascade_slave --compiler_port 9908 >/dev/null 2>&1 &
PID10=$!
sleep 1
./build/tools/cascade --march regression/f1_remote -e share/cascade/test/benchmark/df/df_tb_de10.v >/dev/null 2>&1 &
PID11=$!
sleep 10
./build/tools/cascade --march regression/f1_remote -e share/cascade/test/benchmark/bitcoin/run_30.v >/dev/null 2>&1 &
PID12=$!
sleep 20
kill -9 $PID12
kill -9 $PID11
kill -9 $PID10

# spatial multiplexing, stage 3
nohup ./build/tools/vivado_server --port 9909 >experiments/9909.log 2>&1 &
sleep 1
./build/tools/cascade_slave --compiler_port 9909 >/dev/null 2>&1 &
PID13=$!
sleep 1
./build/tools/cascade --march regression/f1_remote -e share/cascade/test/benchmark/df/df_tb_de10.v >/dev/null 2>&1 &
PID14=$!
sleep 10
./build/tools/cascade --march regression/f1_remote -e share/cascade/test/benchmark/bitcoin/run_30.v >/dev/null 2>&1 &
PID15=$!
sleep 20
./build/tools/cascade --march regression/f1_remote -e share/cascade/test/benchmark/adpcm/adpcm_6M.v >/dev/null 2>&1 &
PID16=$!
sleep 20
kill -9 $PID16
kill -9 $PID15
kill -9 $PID14
kill -9 $PID13

cd $OLD_PWD
echo "All builds have been started"
echo "Please wait until they finish to kill this script"
echo "Progress can be monitored via a task manager"
wait
