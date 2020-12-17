#!/bin/bash

function kill_subproc {
	if [ -n "${VPID}" ]; then
		kill -9 $VPID
	fi
	exit 1
}

{
trap kill_subproc SIGINT SIGQUIT SIGABRT SIGTERM
trap "" SIGHUP

export HOME_DIR=/home/centos/src/project_data
export AWS_FPGA=$HOME_DIR/aws-fpga
export CL_DIR=$(dirname $(readlink -f $0))
#export CL_DIR="${CL_DIR}/"

cd $CL_DIR/build/scripts

# Override return value
#echo "agfi-" >agfi.txt
#echo "afi-" >afi.txt
#exit 0

# Setup HDK env
source $AWS_FPGA/hdk_setup.sh >/dev/null
rm -f awsver.txt

cp $AWS_FPGA/hdk/common/shell_stable/build/scripts/aws_build_dcp_from_cl.sh ./aws_build_dcp_from_cl.sh
rm -f *.log
rm -f ../checkpoints/last_synth.dcp
rm -f ../checkpoints/last_routed.dcp
rm -f ../checkpoints/last_suggestions.rqs

declare -a recipes=("A1" "A0" "A2")
declare -a freqs=("250MHz" "125MHz" "16MHz")
for i in 0 1 2;
do
	date
	echo "Attempting ${freqs[$i]} build..."
	echo ${freqs[$i]} >freq.txt
	#./aws_build_dcp_from_cl.sh -clock_recipe_a ${recipes[$i]} -strategy CONGESTION -foreground >log.txt 2>&1
	#./aws_build_dcp_from_cl.sh -clock_recipe_a ${recipes[$i]} -strategy BASIC -foreground >log.txt 2>&1
	./aws_build_dcp_from_cl.sh -clock_recipe_a ${recipes[$i]} -foreground >log.txt 2>&1 &
	VPID=$!
	wait $VPID
	RC=$?
	TIME=$(basename $(ls -1 *.vivado.log | tail -n 1) .vivado.log)
	mkdir -p ../../../old_logs
	ln $TIME.vivado.log ../../../old_logs/$TIME.vivado.log
	if [ $RC -ne 0 ]; then
		echo "Failed to compile"
		echo $RC >rc.txt
		exit 1
	fi
	grep -s -q "All user specified timing constraints are met." ../reports/$TIME.SH_CL_final_timing_summary.rpt
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "Failed to meet timing"
		continue
	fi
	break
done
if [ $RC -ne 0 ]; then
	echo "Cannot meet timing"
	exit 1
fi

date
aws s3 cp ../checkpoints/to_aws/$TIME.Developer_CL.tar s3://cldesigns/cascade/ --no-progress
AFIS=$(aws ec2 create-fpga-image --region us-east-1 --input-storage-location Bucket=cldesigns,Key=cascade/${TIME}.Developer_CL.tar --logs-storage-location Bucket=cldesigns,Key=logs)

AGFI=$(echo $AFIS | awk '{print $1}')
echo $AGFI >agfi.txt
echo $AGFI
AFI=$(echo $AFIS | awk '{print $2}')
echo $AFI >afi.txt
echo $AFI
wait_for_afi.py --afi $AFI
if [ $? -ne 0 ]; then
	exit 1
fi
date

exit 0
}
