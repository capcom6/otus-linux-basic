#/bin/bash

function show_help {
    NAME_LENGTH=$((41 - `echo "$0" | wc -m`))

    SPACER=`printf ' %.0s' $(seq 1 $NAME_LENGTH)`

    echo "######################################################################"
    echo "# This script allows you to backup MySQL database from slave server  #"
    echo "# Usage $0 [options] [database]$SPACER#"
    echo "#                                                                    #"
    echo "# Options:                                                           #"
    echo "#   -u user - database user                                          #"
    echo "#   -p password - database user password                             #"
    echo "#   -d path - destination directory, current by default              #"
    echo "#                                                                    #"
    echo "######################################################################"

    exit 0
}

function check_errors {
    if [[ $? -ne 0 ]]; then
        echo "!!! There are errors in $ERRORS_LOG:"
        cat $ERRORS_LOG
        exit 1
    fi
}

if [[ $# -lt 1 ]]; then
    show_help
fi

DATABASES=()
while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -u|--user)
        MYSQL_USER="$2"
        shift # past argument
        shift # past value
        ;;
        -p|--password)
        MYSQL_PASSWORD="$2"
        shift # past argument
        shift # past value
        ;;
        -d|--destination)
        DESTINATION="$2"
        shift # past argument
        shift # past value
        ;;
        *)    # unknown option
        DATABASES+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
done

if [[ -z $DESTINATION ]]; then
    DESTINATION=$(pwd)
fi

if ! [ -d $DESTINATION ] || ! [ -w $DESTINATION ]; then
    echo "!!! Directory $DESTINATION is not exists or not writable"
    exit 1
fi

if [[ -z $MYSQL_USER ]]; then
    MYSQL_USER=$USER
fi

if [[ -z $MYSQL_PASSWORD ]]; then
    read -s -p "Enter password: " MYSQL_PASSWORD
    echo ""
fi

ERRORS_LOG=$(mktemp)

echo "Stoping slave"
mysqladmin -u $MYSQL_USER -p$MYSQL_PASSWORD stop-slave 2> $ERRORS_LOG
check_errors


echo "Making dump"
if [ ${#DATABASES[@]} -eq 0 ]; then
    DATABASES=$(mysql -NBA -u $MYSQL_USER -p$MYSQL_PASSWORD -e 'show databases;' 2>> $ERRORS_LOG)
fi

mysql -u $MYSQL_USER -p$MYSQL_PASSWORD -e 'show master status\G;' 2> $ERRORS_LOG > ${DESTINATION}/binlog.pos
check_errors

for DB in $DATABASES
do
    mkdir -p ${DESTINATION}/${DB}
    for TABLE in $(mysql -NBA -u $MYSQL_USER -p$MYSQL_PASSWORD -D $DB -e 'show tables;' 2>> $ERRORS_LOG)
    do
        mysqldump -u $MYSQL_USER -p$MYSQL_PASSWORD $DB $TABLE > ${DESTINATION}/${DB}/${TABLE}.sql 2>> $ERRORS_LOG
        check_errors
    done
done

echo "Starting slave"
mysqladmin -u $MYSQL_USER -p$MYSQL_PASSWORD start-slave 2>> $ERRORS_LOG
check_errors

if [[ -s $ERRORS_LOG ]]; then
    echo "We have some errors in $ERRORS_LOG"
fi

echo "Done!"
