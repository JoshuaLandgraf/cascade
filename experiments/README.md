# Synergy Experiments Guide

## Intro

This guide covers running various experiments shown in our ASPLOS'21 paper. Before proceeding, make sure to set up Synergy according to [ARTIFACT.md](../ARTIFACT.md).

## Scope

Currently, we aim to provide experiments to reproduce the data depicted in the line graphs presented in our paper, as they demonstrate the novel functionality Synergy provides. To make running these experiments as simple as possible, we provide programs that use Synergy's library interface to automate the process of triggering the relevant actions in each experiment.

## Building

Once Synergy has been built, building the experiments is quite simple. The Makefile builds the experiments against the version of Synergy in the local build directory, so installing Synergy isn't necessary to compile them.

    cd /home/centos/src/project_data/cascade-f1/experiments
	source /opt/rh/devtoolset-8/enable
	make

## Experiments

### Suspend and resume

The suspend and resume experiment is broken into two programs: `suspend.cc` and `resume.cc`. The suspend program runs the bitcoin benchmark for some time, triggers a save task that saves the program's state to `state.dat`, and then exits shortly thereafter. The resume program starts running a new instance of bitcoin, triggers a restart task that loads the original program's state from `state.dat`, and resumes executing bitcoin from that checkpoint. Execution should look something like the following:

    $ ./suspend
	...
	Logical Time: 1376256
	Virtual Freq: 49 KHz
	Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "local",__target = "sw"*) 
	Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	<save> root
	<save> root.clock
	Logical Time: 1572864
	Virtual Freq: 49 KHz
	...
	$ ./resume
	...
	Logical Time: 360448
	Virtual Freq: 49 KHz
	Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "local",__target = "sw"*) 
	Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	<restart> root
	<restart> root.clock
	Logical Time: 557056
	Virtual Freq: 49 KHz
	...


### Hardware migration

The hardware migration experiment is carried out by the `migration.cc` program. This experiment starts by creating two hypervisors and executing mips through the first hypervisor. After some time, it triggers a retarget task that migrates execution over to the second hypervisor. Mips then continues to run for a while before the program exits. Execution should look something like the following:

    $ ./migration
	...
	Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "/tmp/fpga_socket",__target = "sw"*) 
	Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	Logical Time: 262144
	Virtual Freq: 131 KHz
	...
	Logical Time: 6422528
	Virtual Freq: 262 KHz
	Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "/tmp/fpga_socket",__target = "sw"*) 
	Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "/tmp/fpga_socket2",__target = "sw"*) 
	Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	Logical Time: 7208960
	Virtual Freq: 393 KHz
	...

### Temporal multiplexing

The temporal multiplexing experiment is implemented in `temporal_multiplexing.cc`. A singe hypervisor is started, along with an instance of the regex benchmark. After regex executes for a while, an instance of the nw benchmark is started on the same hypervisor. These applications contend for execution until nw is terminated. Soon after, regex is stopped as well.

By default, the logs of both regex and nw are printed to the console in real time. This helps with correlating their performance at each point in time, but can make it hard to differentiate their outputs. While logical time can be used to differentiate between the programs, it may be preferable for their output to be logged separately. This can be triggered by the `log_separately` variable in the program, which will make the regex and nw benchmarks log their results to `regex.log` and `nw.log`, respectively. These logs can be monitored in real time time with a command like `less +F regex.log`. Execution should look something like the following if using console output:

    $ ./temporal_multiplexing
	Started logical simulation...
	...
	Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "/tmp/fpga_socket",__target = "sw"*) 
	Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	Logical Time: 2097152
	Virtual Freq: 1 MHz
	...
	Logical Time: 51380224
	Virtual Freq: 2 MHz
	Started logical simulation...
	...
	Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "/tmp/fpga_socket",__target = "sw"*) 
	Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	Logical Time: 70254592
	Virtual Freq: 2 MHz
	Logical Time: 76546048
	Virtual Freq: 1 MHz
	Logical Time: 1
	Virtual Freq: 1024811296905 MHz
	Logical Time: 80740352
	Virtual Freq: 1 MHz
	Logical Time: 4
	Virtual Freq: 1 Hz
    ...

### Spatial multiplexing

The spatial multiplexing experiment is implemented by `spatial_multiplexing.cc`. It is similar to the temporal multiplexing experiment, except the benchmarks do not contend for I/O. A single hypervisor starts by running the df benchmark. After some time, bitcoin starts running through the hypervisor as well. And after some further time, adpcm also starts running through the hypervisor too. After all three programs execute for some time, the program exits. The `log_separately` option is available like before to switch between console and log output for the benchmarks. Execution should look something like the following if using console output:

    ./spatial_multiplexing
	Started logical simulation...
	...
	Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "/tmp/fpga_socket",__target = "sw"*) 
	Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	Logical Time: 131072
	Virtual Freq: 65 KHz
	...
	Logical Time: 2424832
	Virtual Freq: 65 KHz
	Started logical simulation...
	Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "/tmp/fpga_socket",__target = "sw"*) 
	Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	Logical Time: 3735552
	Virtual Freq: 65 KHz
	Logical Time: 8
	Virtual Freq: 1152912709018 MHz
	Logical Time: 3997696
	Virtual Freq: 65 KHz
	Logical Time: 11
	Virtual Freq: 0 Hz
	...
	Logical Time: 31
	Virtual Freq: 1 Hz
	Started logical simulation...
	...
	Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "/tmp/fpga_socket",__target = "sw"*) 
	Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	Logical Time: 21
	Virtual Freq: 709490156619 MHz
	Logical Time: 7405568
	Virtual Freq: 65 KHz
	Logical Time: 63
	Virtual Freq: 0 Hz
	...
