#!/bin/sh

#
# Subversion repository backup script
#
# 15/01/2015 V1.0 - Alessandro Carini
# 19/01/2015 V1.1 - Alessandro Carini (svndumpfile info added in control file)
# 31/01/2015 V1.2 - Improved handling of pathname with spaces
#



# -= Functions =-

# display usage message
usage()
{
	cat << __EOF__
Usage: ${COMMAND} method repository

Available methods:
   -f | --full
   -d | --diff
   --generatelastsaved

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

	if [ ! -r "${controlfile}" ]; then
		errormsg="error: ${controlfile} not found"
		return 4
	fi

	# we need to read the first lines only
	while read -r line
	do
		local cf_line=$(echo "${line}" | awk -F '\[|\:|\]' "/^\[([0-9]|[a-f]|[A-F]|-)+:([0-9])+\]$/ { print \$2 \" \" \$3 }")
		if [ ! -z "${cf_line}" ]; then
read cf_repouuid cf_lastsave << __EOF__
${cf_line}
__EOF__
			errormsg=""
			return 0
		fi

		if [ $(( maxline-=1 )) -le 0 ]; then
			errormsg="error: ${controlfile} bad format"
			return 4
		fi

	done < "${controlfile}"

	errormsg="error: ${controlfile} read past EOF"
	return 4
}

# read repository status
readrepositorystat()
{
	local result=0

	if [ ! -r "${repository}/format" ]; then
		errormsg="error: ${repository} not a SVN repository"
		return 3
	fi

	svnverify="$(svnadmin verify -q "${repository}" 2>&1)"
	if [ $? -ne 0 ]; then
		errormsg="error: ${repository} invalid SVN repository ${svnverify}"
		return 4
	fi

	# get current timestamp and HEAD revision
	repouuid=$(svnlook uuid "${repository}") || { result=$?; errormsg="error: ${repouuid}"; return ${result}; }
	repodate=$(svnlook date "${repository}") || { result=$?; errormsg="error: ${repodate}"; return ${result}; }
	repohead=$(svnlook youngest "${repository}") || { result=$?; errormsg="error: ${repohead}"; return ${result}; }
	svndumpfile=""
	lastsave=-1

	# define control file
	controlfile="${backupdir}/${repouuid}.cf"

	errormsg=""
	return 0
}

# create backup directory
createbackupdir()
{
	local mode="${1}"
	local directory="${backupdir}"
	local result=0

	if [ ! -z "${mode}" ]; then
		directory="${directory}/${mode}"
	fi

	if [ ! -d "${directory}" ]; then
		errormsg=$(mkdir -p "${directory}") || { result=$?; exit ${result}; }
	fi

	errormsg=""
	return 0
}

# write control file
writecontrolfile()
{
	section="[${repouuid}:${repohead}]\nrepodir='${repository}'\nsysdate='${sysdate}'\nrepodate='${repodate}'\n"
	if [ ${lastsave} -ge 0  ]; then
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

	if [ "${method}" = "full" ]; then
		lastsave=0
		svndumpfile="${backupdir}/${method}/${repouuid}.${repohead}"
		parameters="-r${lastsave}:${repohead}"
	elif [ "${method}" = "diff" ] && [ "${repouuid}" = "${cf_repouuid}" ]; then
		lastsave=$(( cf_lastsave + 1 ))
		svndumpfile="${backupdir}/${method}/${repouuid}.${lastsave}-${repohead}"
		parameters="-r${lastsave}:${repohead} --incremental --deltas"
	else
		errormsg="error: internal error"
		return 2
	fi

	# check if dumpfile is already present
	if [ -r "${svndumpfile}.dump" ] || [ -r "${svndumpfile}.dump.gz" ]; then
		errormsg="warning: file ${svndumpfile} already exist"
		return 10
	elif [ ${lastsave} -gt ${repohead} ]; then
		errormsg="warning: revision ${repohead} already saved"
		return 10
	fi

	# create backup directory
	createbackupdir "${method}" || return $?

	# do actual backup - -err file will be removed at the end
	errormsg=$(touch "${svndumpfile}.err") || return $?
	(svnadmin dump -q ${parameters} "${repository}" 2>"${svndumpfile}.err" && rm "${svndumpfile}.err") | gzip > "${svndumpfile}.dump.gz" || { errormsg="error compressing ${svndumpfile}.dump.gz"; exit $?; }

	if [ -e "${svndumpfile}.err" ]; then
		errormsg=$(cat "${svndumpfile}.err")
		rm "${svndumpfile}.err"
		return 4
	fi

	# check if gzip file is correct
	errormsg=$(gzip -t "${svndumpfile}.dump.gz") || return $?

	errormsg=""
	return 0
}


# -= Main =-

SCRIPT=$(readlink -nf "${0}")
HOMEDIR=$(dirname "${SCRIPT}")
COMMAND=$(basename "${SCRIPT}" ".${SCRIPT##*.}")
ARCHIVE="./backup"

if [ ${#} -lt 2 ] || [ "${1}" = "-h" ]; then
	usage
	exit 0
fi

# get configuration in home or /etc directory
if [ -r "${HOMEDIR}/${COMMAND}.conf" ]; then
	. "${HOMEDIR}/${COMMAND}.conf"
elif [  -r "/etc/${COMMAND}.conf" ]; then
	. "/etc/${COMMAND}.conf"
fi

# get sysdate, same format usaed by svn utilities
sysdate=$(date '+%F %T %z (%a, %d %b %Y)')

# truncate trailing '/' after directory name
repository=$(dirname "${2}/.")
backupdir="${ARCHIVE}"/$(basename "${repository}")

# get command
case "${1}" in
	-f|--full)
		method="full"
		readrepositorystat || { result=$?; echo "${errormsg}"; exit ${result}; }
		writerepositorydump || { result=$?; echo "${errormsg}"; exit ${result}; }
		writecontrolfile || { result=$?; echo "${errormsg}"; exit ${result}; }
		;;
	-d|--diff)
		method="diff"
		readrepositorystat || { result=$?; echo "${errormsg}"; exit ${result}; }
		readcontrolfile || { result=$?; echo "${errormsg}"; exit ${result}; }
		writerepositorydump || { result=$?; echo "${errormsg}"; exit ${result}; }
		writecontrolfile || { result=$?; echo "${errormsg}"; exit ${result}; }
		;;
	--generatelastsaved)
		readrepositorystat || { result=$?; echo "${errormsg}"; exit ${result}; }
		writecontrolfile || { result=$?; echo "${errormsg}"; exit ${result}; }
		;;
	*)
		usage
		exit 3;;
esac

echo "done"
exit 0
