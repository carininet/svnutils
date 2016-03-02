#!/bin/bash

#
# Subversion repository backup script
#
# 15/01/2015 V1.0 - Alessandro Carini
# 19/01/2015 V1.1 - Alessandro Carini (svndumpfile info added in control file)
# 31/01/2015 V1.2 - Improved handling of pathname with spaces
# 20/02/2016 V2.0 - Arguments parsed with getopts
#



# -= Functions =-

# display usage message
usage()
{
	cat << __EOF__
Usage: ${MYSELF} <command> [<switches>...] repository

<Commands>
	-h	: Display this message
	-f	: Create full archive backup
	-d	: Create differential backup
	-C	: Build control file *DANGER!*
<Options>
	-b dir	: Override config Use different backupdir
	-v	: Set verbose mode

<Exit Codes>
	0	: success
	1-63	: internal command error
	64	: command line usage error
	65	: data format error
	70	: internal software error
	73	: can't create (user) output file
	74	: input/output error
__EOF__

	errormsg=""
	return 0
}

# read control file content
readcontrolfile()
{
	local line=""
	local maxline=15

	cf_repouuid=""
	cf_lastsave=0

	if [[ ! -r "${controlfile}" ]]; then
		errormsg="error: ${controlfile} not found"
		return 65
	fi

	# we need to read the first lines only
	while read -r line
	do
		local cf_line=$(echo "${line}" | awk -F '\[|\:|\]' "/^\[([0-9]|[a-f]|[A-F]|-)+:([0-9])+\]$/ { print \$2 \" \" \$3 }")
		if [[ ! -z "${cf_line}" ]]; then
read cf_repouuid cf_lastsave << __EOF__
${cf_line}
__EOF__
			errormsg=""
			return 0
		fi

		if [[ $(( maxline-=1 )) -le 0 ]]; then
			errormsg="error: ${controlfile} bad format"
			return 65
		fi

	done < "${controlfile}"

	errormsg="error: ${controlfile} read past EOF"
	return 65
}

# read repository status
readrepositorystat()
{
	local result=0

	if [[ ! -r "${REPOSITORY}/format" ]]; then
		errormsg="error: ${REPOSITORY} not a SVN repository"
		return 65
	fi

	svnverify="$(svnadmin verify -q "${REPOSITORY}" 2>&1)"
	if [[ $? -ne 0 ]]; then
		errormsg="error: ${REPOSITORY} invalid SVN repository ${svnverify}"
		return 65
	fi

	# get current timestamp and HEAD revision
	repouuid=$(svnlook uuid "${REPOSITORY}") || { result=$?; errormsg="error: ${repouuid}"; return ${result}; }
	repodate=$(svnlook date "${REPOSITORY}") || { result=$?; errormsg="error: ${repodate}"; return ${result}; }
	repohead=$(svnlook youngest "${REPOSITORY}") || { result=$?; errormsg="error: ${repohead}"; return ${result}; }
	svndumpfile=""
	lastsave=-1

	# define control file
	controlfile="${BACKUPDIR}/${repouuid}.cf"

	errormsg=""
	return 0
}

# create backup directory
createbackupdir()
{
	local directory="${BACKUPDIR}"
	local result=0

	if [[ ! -z "${method}" ]]; then
		directory="${directory}/${method}"
	fi

	if [[ ! -d "${directory}" ]]; then
		errormsg=$(mkdir -p "${directory}") || { result=$?; exit ${result}; }
	fi

	errormsg=""
	return 0
}

# write control file
writecontrolfile()
{
	section="[${repouuid}:${repohead}]\nrepodir='${REPOSITORY}'\nsysdate='${sysdate}'\nrepodate='${repodate}'\n"
	if [[ ${lastsave} -ge 0  ]]; then
		section="${section}svndumpfile='${svndumpfile}'\nrevision=${lastsave}:${repohead}\n"
	fi

	createbackupdir "" || return $?
	errormsg=$(touch "${controlfile}" && echo -e "${section}" > "${controlfile}.tmp" && cat "${controlfile}" >> "${controlfile}.tmp" && mv "${controlfile}.tmp" "${controlfile}") || return $?

	errormsg=""
	return 0
}

# write a gzipped dump file
writerepositorydump()
{
	local parameters=""

	if [[ "${method}" = "full" ]]; then
		lastsave=0
		svndumpfile="${BACKUPDIR}/${method}/${repouuid}.${repohead}"
		parameters="-r${lastsave}:${repohead}"
	elif [[ "${method}" = "diff" ]] && [[ "${repouuid}" = "${cf_repouuid}" ]]; then
		lastsave=$(( cf_lastsave+1 ))
		svndumpfile="${BACKUPDIR}/${method}/${repouuid}.${lastsave}-${repohead}"
		parameters="-r${lastsave}:${repohead} --incremental --deltas"
	else
		errormsg="error: internal error"
		return 70
	fi

	# check if dumpfile is already present
	if [[ -r "${svndumpfile}.dump" ]] || [[ -r "${svndumpfile}.dump.gz" ]]; then
		errormsg="file ${svndumpfile} already exist"
		return 73
	elif [[ ${lastsave} -gt ${repohead} ]]; then
		errormsg="revision ${repohead} already saved"
		return 73
	fi

	# create backup directory
	createbackupdir "${method}" || return $?

	# do actual backup - -err file will be removed at the end
	errormsg=$(touch "${svndumpfile}.err") || return $?
	(svnadmin dump -q ${parameters} "${REPOSITORY}" 2>"${svndumpfile}.err" && rm "${svndumpfile}.err") | gzip > "${svndumpfile}.dump.gz" || { errormsg="error compressing ${svndumpfile}.dump.gz"; exit $?; }

	if [[ -e "${svndumpfile}.err" ]]; then
		errormsg=$(cat "${svndumpfile}.err")
		rm "${svndumpfile}.err"
		return 74
	fi

	# check if gzip file is correct
	errormsg=$(gzip -t "${svndumpfile}.dump.gz") || return $?

	errormsg=""
	return 0
}


# -= Main =-

# Get script name
SCRIPT=$(readlink -nf "${0}")
HOMEDIR=$(dirname "${SCRIPT}")
MYSELF=$(basename "${SCRIPT}" ".${SCRIPT##*.}")

# Get configuration
ARCHIVE="./backup"
if [[ -r "${HOMEDIR}/${MYSELF}.conf" ]]; then
	. "${HOMEDIR}/${MYSELF}.conf"
elif [[ -r "/etc/${MYSELF}.conf" ]]; then
	. "/etc/${MYSELF}.conf"
fi

COMMAND=""
REPOSITORY=""
VERBOSITY=0

# Parse command line
while getopts ':hfdCb:v' opt; do
	case "${opt}" in
		'h'|'f'|'d'|'C')
			COMMAND="${opt}${COMMAND}" 
			;;
		'b')
			ARCHIVE="${OPTARG}"
			;;
		'v')
			(( VERBOSITY+=1 ))
			;;
		*)
			echo "Invalid command arguments (${MYSELF} -h for help)"
			exit 64
			;;
	esac
done

# Get pathnames
REPOSITORY=$(dirname "${!OPTIND}/.")
BACKUPDIR="${ARCHIVE}"/$(basename "${REPOSITORY}")

# get sysdate, same format usaed by svn utilities
sysdate=$(date '+%F %T %z (%a, %d %b %Y)')

case "${COMMAND}" in
	'h')
		usage; exit 0
		;;
	'f')
		method="full"
		readrepositorystat || { result=$?; echo "${errormsg}"; exit ${result}; }
		writerepositorydump || { result=$?; echo "${errormsg}"; exit ${result}; }
		writecontrolfile || { result=$?; echo "${errormsg}"; exit ${result}; }
		;;
	'd')
		method="diff"
		readrepositorystat || { result=$?; echo "${errormsg}"; exit ${result}; }
		readcontrolfile || { result=$?; echo "${errormsg}"; exit ${result}; }
		writerepositorydump || { result=$?; echo "${errormsg}"; exit ${result}; }
		writecontrolfile || { result=$?; echo "${errormsg}"; exit ${result}; }
		;;
	'C')
		readrepositorystat || { result=$?; echo "${errormsg}"; exit ${result}; }
		writecontrolfile || { result=$?; echo "${errormsg}"; exit ${result}; }
		;;
	*)
		echo "Invalid command arguments (${MYSELF} -h for help)"
		exit 64
		;;
esac

echo "done"
exit 0
