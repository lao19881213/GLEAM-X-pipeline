#! /bin/bash

usage()
{
echo "obs_manta.sh [-d dep] [-q queue] [-s timeave] [-k freqav] [-t] -o list_of_observations.txt
  -d dep      : job number for dependency (afterok)
  -q queue    : job queue, default=workq
  -s timeav   : time averaging in sec. default = 2 s
  -k freqav   : freq averaging in KHz. default = 40 kHz
  -t          : test. Don't submit job, just make the batch file
                and then return the submission command
  -o obslist  : the list of obsids to process" 1>&2;
exit 1;
}

# Supercomputer options
if [[ "${HOST:0:4}" == "gala" ]]
then
    computer="galaxy"
    account="mwasci"
    standardq="workq"
    absmem=60
    scratch="/astro"
    group="/group"
#    standardq="gpuq"
#    absmem=30
elif [[ "${HOST:0:4}" == "magn" ]]
then
    computer="magnus"
    account="pawsey0272"
    standardq="workq"
    absmem=60
    scratch="/astro"
    group="/group"
elif [[ "${HOST:0:4}" == "athe" ]]
then
    computer="athena"
    account="pawsey0272"
    standardq="gpuq"
    absmem=30 # Check this
    scratch="/astro"
    group="/group"
fi

#initial variables

base="$scratch/mwasci/$USER/GLEAMX/"
code="$group/mwasci/$USER/GLEAM-X-pipeline/"
dep=
queue="-p $standardq"
tst=
timeav=
freqav=

# parse args and set options
while getopts ':td:s:k:o:' OPTION
do
    case "$OPTION" in
    d)
        dep=${OPTARG} ;;
	q)
	    queue="-p ${OPTARG}" ;;
	s)
	    timeav=${OPTARG} ;;
	k)
	    freqav=${OPTARG} ;;
	o)
	    obslist=${OPTARG} ;;
    t)
        tst=1 ;;
        ? | : | h)
            usage ;;
  esac
done

# set the obsid to be the first non option
#shift  "$(($OPTIND -1))"
#obsnum=$1

# if obslist is not specified or an empty file then just print help

if [[ -z ${obslist} ]] || [[ ! -s ${obslist} ]] || [[ ! -e ${obslist} ]]
then
    usage
else
    numfiles=`wc -l ${obslist} | awk '{print $1}'`
fi

if [[ ! -z ${dep} ]]
then
    depend="--dependency=afterok:${dep}"
fi

cd $base
list=`cat $obslist`
if [[ -e ${obslist}_manta.tmp ]] ; then rm ${obslist}_manta.tmp ; fi
# Set up telescope-configuration-dependent options
# Might use these later to get different metafits files etc
for obsnum in $list
do
    if [[ $obsnum -lt 1151402936 ]] ; then
        telescope="MWA128T"
        basescale=1.1
        freqres=40
        timeres=4
    elif [[ $obsnum -ge 1151402936 ]] && [[ $obsnum -lt 1191580576 ]] ; then
        telescope="MWAHEX"
        basescale=2.0
        freqres=40
        timeres=8
    elif [[ $obsnum -ge 1191580576 ]] ; then
        telescope="MWALB"
        basescale=0.5
# Testing ionospheric effects with bright sources
        freqres=40
        timeres=1
    fi
    if [[ -d ${obsnum}/${obsnum}.ms ]]
    then
        echo "${obsnum}/${obsnum}.ms already exists. Please delete any existing measurement sets before running this script."
        exit 1
    else
# start download
        echo "obs_id=${obsnum}, job_type=c, timeres=${timeres}, freqres=${freqres}, edgewidth=80, conversion=ms, allowmissing=true, flagdcchannels=true" >>  ${obslist}_manta.tmp
    fi
done

listbase=`basename ${obslist}`
listbase=${listbase%%.*}
script="${code}queue/manta_${listbase}.sh"

cat ${code}/bin/manta.tmpl | sed -e "s:OBSLIST:${obslist}:g" \
                                 -e "s:BASEDIR:${base}:g"  > ${script}
#                                 -e "s:ACCOUNT:${account}:g"

output="${code}queue/logs/manta_${listbase}.o%A"
error="${code}queue/logs/manta_${listbase}.e%A"

#sub="sbatch --begin=now+15 --output=${output} --error=${error} ${depend} ${queue} ${script}"
sub="sbatch --output=${output} --error=${error} ${depend} ${queue} ${script}"
if [[ ! -z ${tst} ]]
then
    echo "script is ${script}"
    echo "submit via:"
    echo "${sub}"
    exit 0
fi

# submit job
jobid=($(${sub}))
jobid=${jobid[3]}

# rename the err/output files as we now know the jobid
error=`echo ${error} | sed "s/%A/${jobid}/"`
output=`echo ${output} | sed "s/%A/${jobid}/"`

# record submission
n=1
for obsnum in $list
do
    python ${code}/bin/track_task.py queue --jobid=${jobid} --taskid=${n} --task='download' --submission_time=`date +%s` --batch_file=${script} \
                     --obs_id=${obsnum} --stderr=${error} --stdout=${output}
    ((n+=1))
done

echo "Submitted ${script} as ${jobid}. Follow progress here:"
echo $output
echo $error
