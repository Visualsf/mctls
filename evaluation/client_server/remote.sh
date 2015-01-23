#!/bin/bash 

# Function to print script usage
usage(){
    echo -e "Usage: $0 opt run [plotCommand]"
    echo -e "opt  = test to be run "
	echo -e "\t(0) Test number of connections per second concurrently on machines from file <<machines>>"
    echo -e "run  = {(1) run test and collect results ; (0) colect results only}"
	echo -e "[plotCommand = {matlab, myplot, ...} add your own to the script (default is no plotting)]"
	exit 0 
}
	
# Set of checks for correctness
[[ $# -lt 2 ]] && usage

# Static parameters
resFolder="../results"    # result folder 
opt=$1                    # user choice for experiment
RUN_EXP=$2                # run experiment or not 
plotCommand="none"        # Usere selection for plotting 
key="amazon.pem"          # amazon key 
machineFile="machines"
remoteFolder="./secure_proxy_protocol/evaluation/client_server"
localFolder="./WorkTelefonica/HTTP-2/sigcomm_evaluation/secure_proxy_protocol/evaluation/client_server"
protoList[1]="ssl"        # array for protocol types currently supported
protoList[2]="fwd"
protoList[3]="spp"
protoList[4]="pln"
parallel=1                # flag for matlab plotting 

# read type of plot to do 
if [ $# -eq 3 ]
then 
	plotCommand=$3
fi

# derive proto size 
proto_count=${#protoList[@]}

# no run if u only want to plot 
if [ $RUN_EXP -eq 1 ] 
then
# switch on user selection 
	case $opt in 
	0)
    	echo "[REMOTE] Test number of connections per second on multiple machines (in parallel)"
		machines=0
		if [ -f .active ] 
		then 
			rm .active
		fi
		for line in `cat $machineFile`
		do
			addr=`echo $line | cut -f 2 -d "@" | cut -f 1 -d ":"`
			port=`echo $line | cut -f 2 -d "@" | cut -f 2 -d ":"`
			user=`echo $line | cut -f 1 -d "@"`
			log="log_master_"$addr
			if [ $addr == "localhost" ] 
			then 
				comm="cd $localFolder; ./master.sh 7 0 1"
			else
				comm="cd $remoteFolder; ./master.sh 7 0 1"
			fi

			echo "$addr 1" >> .active
			if [ -f $log ] 
			then 
				rm $log 
			fi
			echo "[REMOTE] Started script at machine $addr (user=$user ; port=$port)"
			if [ $addr == "tid.system-ns.net" -o $addr == "localhost" ]
			then  
				ssh -o StrictHostKeyChecking=no -p $port $user@$addr $comm >> $log 2>&1 &
			else 
				ssh -o StrictHostKeyChecking=no -p $port -i $key $user@$addr $comm >> $log 2>&1 &
			fi
			let "machines++"
		done

		# check that experiment is completed everywhere 
		echo "[REMOTE] Active machines: "
		cat .active
		found=0
		while [ $found -lt $machines ] 
		do
			echo "[REMOTE] $found machines have already completed"
			for line in `cat $machineFile`
			do
				addr=`echo $line | cut -f 2 -d "@" | cut -f 1 -d ":"`
				status=`cat .active | grep "$addr" | cut -f 2 -d " "`
				if [ $status -eq 1 ]
				then  
					active=`ps aux | grep ssh | grep master | grep "$addr" | grep -v grep | wc -l`
					echo "[REMOTE] Checking machine $addr. Status: $active (0=DONE, 1=STILL_WORKING)"
					if [ $active -eq 0 ] 
					then
						let "found++"
						echo "[REMOTE] Machine $addr is done (counter=$found)"
						echo "$addr 0" >> .active_new
					else
						echo "$addr 1" >> .active_new
					fi	
				fi 
				sleep 2
			done
			mv .active_new .active 
		done
		;;
	esac
fi

# Fetch results 
rf="./secure_proxy_protocol/evaluation/results/"
lf="./WorkTelefonica/HTTP-2/sigcomm_evaluation/secure_proxy_protocol/evaluation/results/"
resFolder="../results"
for line in `cat $machineFile`
do
	addr=`echo $line | cut -f 2 -d "@" | cut -f 1 -d ":"`
	port=`echo $line | cut -f 2 -d "@" | cut -f 2 -d ":"`
	user=`echo $line | cut -f 1 -d "@"`
	for ((i=1; i<=proto_count; i++))
	do
		proto=${protoList[$i]}
		if [ $addr == "localhost" ] 
		then 
			file=$lf"res_"$proto"_connections_slice"
		else
			file=$rf"res_"$proto"_connections_slice"
		fi
		targetFile=$resFolder"/res_"$proto"_connections_slice_"$addr
		if [ $addr == "tid.system-ns.net" -o $addr == "localhost" ]
		then 
			scp -P $port  $user@$addr:$file $targetFile
		else 
			scp -P $port  -i $key $user@$addr:$file $targetFile
		fi
	done
done

# Plotting results 
# TO DO 
if [ $plotCommand == "matlab" ] 
then 
	echo "[MASTER] Plotting results (option $opt)"
	echo "[MATLAB] Running MATLAB...(it can take some time first time)"
	matlab -nodisplay -nosplash -r "cd $resFolder; plotSigcomm($opt, $remote, $parallel); quit"

	# Generating summary report 
	cd ../results 
	../results/script.sh 
	cd - 
else 
	echo "[MASTER] No plotting requested or plotting type <<$plotCommand>> not supported"
fi