# Synergy Artifact Evaluation Guide for AWS F1 Platform

## Intro

This guide will walk you through how to set up Synergy on an AWS F1 instance. We assume users have already set up an AWS account and have minimal familiarity with AWS EC2 and S3. You will need your AWS Access Key ID and Secret Access Key to set up the AWS CLI. While the AMI we use does not have software costs, F1 instances cost ~$1.65/hour. Replicating our experiments could take a few days, mostly due to Vivado compilation times for larger builds.

## Creating the instance

First, you will need to create an AWS instance to run Synergy on. Set it up based on the [AWS FPGA Developer AMI](https://aws.amazon.com/marketplace/pp/Amazon-Web-Services-FPGA-Developer-AMI/B06VVYBLZZ) as follows:

- Continue to Subscribe.
- Continue to Configuration.
- Select Software Version 1.7.1, newer versions may not work properly.
- Select a Region containing F1 instances. We use US East (N. Virginia).
- Continue to Launch.
- Launch through EC2. This enables additional configuration options.
- Choose Instance Type: f1.2xlarge.
- Configure Instance Details.
- Select a Subnet containing F1 instances. We use us-east-1c. Do not select "No preference" as it may use us-east-1f, which does not contain F1 instances.
- Add Storage.
- The default setup has a Root / OS volume and an EBS / data volume. F1 instances also provide an ephemeral NVMe volume, which we do not use. Unless you plan to install a GUI, 75GB should be sufficient for the Root volume. We recommend expanding the data volume from 5 to 30GB, which should be sufficient to store the generated data for many builds.
- Add Tags if you wish.
- Configure Security Group. Create or Select a security group that allows all inbound SSH traffic. This should be fine since you can only authenticate via private key.
- Review and Launch.
- Choose or Create a key pair.
- Download Key Pair (if creating a new one) and Launch Instances. We assume the key is named eval_key(.pem).
- `mv Downloads/aws_key.pem ~/.ssh/eval_key.pem`
- `chmod 600 ~/.ssh/eval_key.pem`
- Your instance should now be running, and you should be ready to connect to it.

## Using the instance

- Find your instance in the AWS console under Services --> EC2 --> Instances --> Instances.
- If it is not already Running, select the instance and use Instance state --> Start instance.
- It may take a minute for the instance to start, be marked as Running, and Status check to pass. You may need to refresh the AWS console to see the updated status.
- With the Instance selected and running, a Public IPv4 DNS should be available under Details --> Instance summary.
- You may want to set up an Elastic IP for the instance so that the IP and DNS addresses do not change.
- `ssh -i ~/.ssh/eval_key.pem centos@<Public IPv4 DNS>`
- Confirm the key fingerprint. If you do not have an elastic IP, this will likely change every time the instance is started.
- You should now be logged into your instance.
- The instance can be stopped with `sudo shutdown now` or by using Instance state --> Stop instance in the AWS console.

## Setting up the environment

Synergy is a continuation of the original Cascade project, which was originally intended for use with Ubuntu and macOS. This means setting up its dependencies on CentOS 7 is a little tricky.

- Make sure your instance is started and connect to it.
- `sudo yum -y update`
- `sudo yum -y install centos-release-scl`
- Wait for centos-release-scl to be installed before devtoolset-8 can be installed.
- `sudo yum -y install devtoolset-8 cmake3 bison gtest-devel`
- Synergy expects cmake3 to be the default on the system. This can be done manually in CentOS.
- `sudo alternatives --install /usr/local/bin/cmake cmake /usr/bin/cmake3 20 --slave /usr/local/bin/ctest ctest /usr/bin/ctest3 --slave /usr/local/bin/cpack cpack /usr/bin/cpack3 --slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake3 --family cmake`
- `sudo alternatives --install /usr/local/bin/cmake cmake /usr/bin/cmake 10 --slave /usr/local/bin/ctest ctest /usr/bin/ctest --slave /usr/local/bin/cpack cpack /usr/bin/cpack --slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake --family cmake`
- Synergy also requires google-benchmark, which isn't available as an RPM for CentOS 7. We will build release 1.5.2 instead.
- `cd /home/centos/src/project_data/`
- `git clone https://github.com/google/benchmark.git google-benchmark`
- `cd google-benchmark/`
- `git checkout 73d4d5e8d6d449fc8663765a42aa8aeeee844489`
- `git clone https://github.com/google/googletest.git benchmark/googletest`
- `cd googletest/`
- `git checkout 703bd9caab50b139428cea1aaff9974ebee5742e`
- `cd ..`
- `cmake -E make_directory "build"`
- `cmake -E chdir "build" cmake -DCMAKE_BUILD_TYPE=Release ../`
- `cmake --build "build" --config Release`
- `sudo /usr/local/bin/cmake --build "build" --config Release --target install`
- `cd ..`
- `rm -rf google-benchmark`
- We also need a newer version of flex than what is available on CentOS 7. A sufficiently compatible RPM can be obtained from CentOS 8.
- `sudo yum -y install http://mirror.centos.org/centos/8/AppStream/x86_64/os/Packages/flex-2.6.1-9.el8.x86_64.rpm`
- You will need to configure the AWS CLI on your machine to be able to access S3.
- `pip install --user --upgrade boto3`
- `aws configure`
- Enter the Access Key ID and Secret Access Key associated with your account.
- Default region name: `us-east-1` (or appropriate region if not using N. Virginia).
- Default output format: `text`
- AWS requires you have an S3 bucket and folder to place compiled designs in. This can be created on the AWS console under Services --> S3 ---> Create bucket.
- Use the Bucket name: `cldesigns`
- Select Region: `us-east-1` or your appropriate alternative.
- Create bucket.
- Enter the cldesigns bucket in the AWS console.
- Create a folder for the automatically-generated design files.
- Use the Folder name: `cascade`
- Create folder.
- You should now be able to see this folder from your AWS instance with: `aws s3 ls cldesigns`
- Finally, Synergy requires you to set up the aws-fpga repo inside your project_data folder.
- `cd /home/centos/src/project_data/`
- `git clone https://github.com/aws/aws-fpga.git`
- `cd aws-fpga/`
- `git checkout 1f67d8e375be81176a9f672544d870dfb24303e8`
- `source sdk_setup.sh`
- Make sure you see: `INFO: sdk_setup.sh PASSED`
- `source hdk_setup.sh`
- This will take several minutes. Make sure you see: `INFO: AWS HDK setup PASSED.`
- `cd ..`
- The environment should now be set up. You can verify the FPGA tools are available by running `sudo fpga-describe-local-image -S 0 -H`, which should show a local FPGA with a cleared image.

## Setting up Synergy

With the dependencies installed, we can now build and install Synergy / Cascade.

- `cd /home/centos/src/project_data/`
- `git clone https://github.com/JoshuaLandgraf/cascade.git cascade-f1`
- `cd cascade-f1/`
- `git checkout artifact`
- Synergy requires a newer version of GCC than what is available by default on CentOS 7. You will need to set your environment to default to a newer set of dev tools to proceed.
- `source /opt/rh/devtoolset-8/enable`
- `./setup`
- Select the option to build Synergy / Cascade.
- You can optionally run the built-in tests during the setup. They usually take a few minutes to complete. You can also run the tests (with more detailed output) after the setup completes with `./build/test/run_regression`.
- Select the option to install Cascade / Synergy.
- To re-run the build / install, you can run `make -C ./build [install]` from the `cascade-f1` directory. Alternatively, you can `rm -rf ./build` and re-run `./setup`

## Running Synergy

Synergy consists of three main executable files: `cascade`, `cascade_slave`, and `vivado_server`. The first, `cascade`, is similar to the original Cascade JIT compiler and is the frontend for running Verilog programs. The second, `cascade_slave`, is Synergy's optional hypervisor. It enables multiple instances of `cascade` to share a single FPGA. Finally, `vivado_server` handles compiling a program for `cascade` or `cascae_slave`. This is provided as a separate component so that compilations can be run on a remote machine with potentially better performance (e.g. AWS' Z1D instances).

### Configuring `vivado_server`

Before being able to use the F1 backend, we need to configure and run `vivado_server` so `cascade` can build bitstreams to deploy on the FPGA. By default, `vivado_server` maintains its builds and cache locally in the `/tmp/f1` directory. These paths can be overridden with the `--path <path1>` and `--cache <path2>` options, though this can get tedious. We recommend creating a directory with `mkdir /home/centos/src/project_data/cache` and making a symlink with `ln -s /home/centos/src/project_data/cache /tmp/f1`. This makes it easier to examine the output of builds while reducing the chance that cached build data will get deleted.

This leaves the parameter `--port <num>`, which controls the port `vivado_server` listens on. By changing this port, you can run several instances of `vivado_server` concurrently, which is useful for performing builds in parallel. The port number is also used to determine the build directory name within the specified build path. By using different port numbers for different builds, you can ensure that previous builds do not get overwritten so you can examine their log files afterward.

Due to how long FPGA builds can take, we recommend running `vivado_server` inside `screen` so that the build will not be killed if your SSH connection is interrupted. It is also worth noting that `vivado_server` will continue compiling even if it loses its connection to `cascade` or `cascade_slave` and only kills a build when it received an updated one. If you'd like to populate the build cache in parallel and upfront, you only need `cascade` to run long enough to kick off the build. The `cascade` process can then be killed (via kill or killall) so the CPU doesn't waste cycles on simulation (`vivado_server` currently ignores build kill requests from `cascade` if you try to kill it with ctrl-c). The build result will be stored in the cache when it completes, and will be ready the next time `cascade` is run. An f1.2xlarge instance can accommodate about 2-6 simultaneous builds depending on whether you want to optimize for build time or machine utilization. If you plan on doing lots of builds, you can also temporarily switch to a larger F1 instance by stopping the current instance, selecting the instance in the AWS console, and using Actions --> Instance settings --> Change instance type. The f1.2xlarge, f1.4xlarge, and f1.16xlarge instances provide 8, 16, and 64 virtual cores, respectively. Vivado uses between 1 to 8 virtual cores over the course of a compilation, so compilations shouldn't benefit from reserving more than 8 virtual cores for it.

If you would like to examine the logs from a compilation, you can find them in the `cache` directory under `vivado_server`'s port number. The Vivado build log can be found in `build/scripts/<date-time>.vivado.log` along with files containing the AGFI and AFI identifiers for the generated bitstream. Timing and resource usage reports can be found under `build/reports/` and are named `<date-time>.SH_CL_final_timing_summary.rpt` and `<date-time>.SH_CL_all_utilization_aos.rpt`, respectively. Finally, you can check the Verilog generated by Synergy under `design/program_logic.v`.

### Configuring `cascade`

The `cascade` program has many configuration options. However, for our evaluation, only a couple are needed.

- `--march <arch>` specifies the target execution environment based on configuration files in `share/cascade/march/`. For single applications where no hypervisor is needed, the arch is generally set to `regression/f1_minimal`. This goes straight from software simulation to hardware. The regular `f1` arch uses Verilator as an intermediate step, but this interferes with measuring hardware performance and can be buggy. The `regression/f1_remote` arch is used to connect to a hypervisor for execution.
- `-I <path>` specifies the search path for program files. When running in the root of the `cascade` directory, it is generally not needed. Otherwise, it should be set to `/home/centos/src/project_data/cascade-f1`.
- `-e <path/to/file.v>` specifies the path of the top-level Verilog file to run.
- `--compiler_port <port>` specifies the port number of the `vivado_server` to connect to. If compiling through a hypervisor, this is not needed as the hypervisor will initiate the builds.
- `--enable_info` enables extra output messages, like notifications when `cascade` switches backends or profiling data.
- `--profile <seconds>` enables profiling and logs the virtual program frequency at the specified interval. It is recommended to set this to at least 2 since logging is decoupled from the 1-second scheduling quantum, leading to aliasing issues with a 1s logging interval.

### Configuring `cascade_slave`

The `cascade_slave` program has a few notable configuration options as well.

- `--slave_port <port>` allows assigning a unique port for when multiple hypervisors are in use.
- `--compiler_fpga <index>` allows setting the index of the FPGA being managed (starting at 0).
- `--compiler_port <port>` works the same way as for `cascade`.

### Running virtualization experiments

With Synergy up and running, you can begin running the experiments presented in the paper. These experiments have been automated using the `libcascade` C++ library interface and can be found in the `experiments` directory. The [README.md](./experiments/README.md) there documents how the experiments work and what the output of the experiments should look like. It also contains a script that helps automate the process of populating Synergy's bitstream cache. You may want to run this script before running benchmarks standalone.

### Running benchmarks standalone

First, start up some `vivado_server` instances. If you have already pre-populated the bitstream cache, a single, instance of `vivado_server` is fine as it only needs to return results from the cache. If you would like to manually generate bitstreams for each application, we recommend creating an instance of `vivado_server` for each application in separate `screen`, `tmux`, or `nohup` sessions, as the builds can take a few hours.

    (screen 1) vivado_server --port 9901
    (screen 2) vivado_server --port 9902
    (screen 3) vivado_server --port 9903
    (screen 4) vivado_server --port 9904
    (screen 5) vivado_server --port 9905
    (screen 6) vivado_server --port 9906

These `vivado_server` instances will run in the foreground until killed with `ctrl-c` or `fuser -k <port>/tcp`. It can take a minute for the port to be freed by the OS after `vivado_server` is killed, so starting a new server with the same port shortly afterward may result in it exiting unexpectedly. If this happens, simply wait a minute for the OS to reclaim the port before retrying if this happens.

The Verilog and data files for our benchmarks can be found in `share/cascade/test/benchmark`. Each of the 6 main benchmarks can be run as shown below. Note that running multiple instances of cascade with an F1 backend can cause issues if they both try to use the FPGA at the same time. When running on an instance that has multiple FPGAs (e.g. f1.4xlarge), you can use the `--compiler_fpga <index>` option with `cascade` to have applications run on separate FPGAs concurrently.

    cd /home/centos/src/project_data/cascade-f1
    cascade --march regression/f1_minimal -e share/cascade/test/benchmark/adpcm/adpcm_6M.v --compiler_port 9901 --enable_info --profile 2
    cascade --march regression/f1_minimal -e share/cascade/test/benchmark/bitcoin/run_30.v --compiler_port 9902 --enable_info --profile 2
    cascade --march regression/f1_minimal -e share/cascade/test/benchmark/df/df_tb_de10.v --compiler_port 9903 --enable_info --profile 2
    cascade --march regression/f1_minimal -e share/cascade/test/benchmark/mips32/run_bubble_128_32768.v --compiler_port 9904 --enable_info --profile 2
    cascade --march regression/f1_minimal -e share/cascade/test/benchmark/nw/run_8.v --compiler_port 9905 --enable_info --profile 2
    cascade --march regression/f1_minimal -e share/cascade/test/benchmark/regex/run_disjunct_64.v --compiler_port 9906 --enable_info --profile 2

The output from `cascade` should resemble the following (from `bitcoin/run_25.v` with a cached bitstream):

	>>> Started logical simulation...
	>>> Installation Path: /usr/local/bin/../
	>>> Fopen dirs:        ./:
	>>> Include dirs:      /usr/local/bin/../:share/cascade/test/benchmark/bitcoin
	>>> C++ Compiler:      /opt/rh/devtoolset-8/root/usr/bin/c++
	>>> Typechecker Warning:
	>>>   > In module declaration in share/cascade/test/benchmark/bitcoin/sha256_transform.v on line 104: HASHERS[((64 / LOOP) - 32'd1)].state[31:0]
	>>>     Found reference to unresolvable identifier, this may result in an error during instantiation
	>>> Typechecker Warning:
	>>>   > In module declaration in share/cascade/test/benchmark/bitcoin/bitcoin.v on line 4: clock.val
	>>>     Found reference to unresolvable identifier, this may result in an error during instantiation
	>>>   > In module declaration in share/cascade/test/benchmark/bitcoin/bitcoin.v on line 3: clock.val
	>>>     Found reference to unresolvable identifier, this may result in an error during instantiation
	>>> Finished pass 1 compilation of root with attributes (*__std = "logic",__loc = "local",__target = "sw"*) 
	>>> Finished pass 1 compilation of root.clock with attributes (*__std = "clock",__loc = "local",__target = "sw"*) 
	>>> <save> root
	>>> <save> root.clock
	>>> Deploying agfi-0cb6b320838b75b84 to fpga 0
	<restart> root
	>>> <restart> root.clock
	>>> Logical Time: 4096
	>>> Virtual Freq: 4611686018423 MHz
	>>> Finished pass 2 compilation of root with attributes (*__std = "logic",__loc = "local",__target = "f1"*) 
	>>> Logical Time: 402661374
	>>> Virtual Freq: 67 MHz
	>>> Logical Time: 805314558
	>>> Virtual Freq: 100 MHz
	>>> 0109a2bd 0109a2c2
	>>> Finished logical simulation
	>>> Requesting stop for all outstanding compilation jobs... OK
	>>> Requesting stop for all asynchronous compilation tasks... OK
	>>> Tearing down program... OK
	>>> Tearing module hierarchy... OK
	>>> Goodbye!

When `cascade` runs, it starts simulation immediately and begins parsing the program. Typechecker warnings when running our benchmarks can generally be ignored. The first virtual frequency reported will be very large since the clock can toggle quickly before there is a program to execute. Once the program has been parsed, we get a message indicating the first compilation pass has succeeded, with the target being local software execution. In this case, the bitstream for F1 is already cached, so pass 2, targeting local FPGA execution, proceeds immediately. The program is stopped, its state is saved, the bitstream is deployed to the FPGA, the program's state is restored on the FPGA, and the program restarts execution. We are then notified that pass 2 has completed. Eventually, the program, bitcoin, finds the nonce it was searching for, prints it out, and terminates.

It is worth noting that logical time is incremented every time the clock goes up or down. Since frequency is measured in full clock cycles (posedge and negedge), the frequency will be half the logical time passed between two points in time. With a profile interval of 2, logical time is reported every two seconds, so we see 100MHz * 2s * 2 flips per clock = ~400M clock flips between the last two reported logical times.

The bitcoin, mips32, nw, and regex benchmark directories contain README.txt files documenting their expected outputs for a number of configurations, allowing you to validate their output. They should generally run on the order of seconds to a few minutes on the FPGA, with the exception of regex. Lower loop count configurations of regex can complete execution in software before transitioning to the FPGA, even with the bitstream cached. However, higher loop count configurations can run for a very long time once execution has transitioned to the FPGA due to regex being communication-bound, so we don't recommend trying to run regex to completion at this time.