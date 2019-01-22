#!/bin/bash

#
# wrapper for p2rank-to-funpdbe.py
# creates log file for each processed p2rank result
#
# $1 ... number of threads
# $2 ... input dir (containing p2rank output csv filrd)
# $3 ... output dir (doesn't have to exist)
#


export THREADS=$1
export INPUT=$2
export OUT=$3

export OUT_FUNPDBE=$OUT/funpdbe
export OUT_ERROR=$OUT/error
export OUT_LOG=$OUT/log-success
export OUT_LOG_FAILED=$OUT/log-failed

mkdir -p $OUT
mkdir -p $OUT_LOG
mkdir -p $OUT_LOG_FAILED


# set env.
export PYTHONPATH="$PWD/funpdbe-validator"
export PYTHON_CMD=python3


format_time() {
  local T=$1
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  (( $D > 0 )) && printf '%d days ' $D
  (( $H > 0 )) && printf '%d hours ' $H
  (( $M > 0 )) && printf '%d min ' $M
  (( $D > 0 || $H > 0 || $M > 0 ))
  printf '%d s\n' $S
}

# find number of errors
find_errors() {
    SEARCH_STR="$1"
    grep "$SEARCH_STR" -r $OUT_LOG_FAILED -l | wc -l
}


process_pdb_id() {

    # run p2rank-to-funpdbe
    PDBID=$1
    LOGF=$OUT_LOG/$PDBID.log
    $PYTHON_CMD p2rank-to-funpdbe/p2rank-to-funpdbe.py \
        --threads 1 \
        --input $INPUT \
        --pdbId $PDBID \
        --output $OUT_FUNPDBE \
        --errorOutput $OUT_ERROR &> $LOGF

    # zip json and move log if failed    
    RESULTF=$OUT_FUNPDBE/$PDBID.json
    if [ -f $RESULTF ]; then
        gzip -9 $RESULTF
        rm -f $LOGF # no need to keep logs of sccessful runs
        echo "$PDBID: OK"
    else 
        RESULTF=$OUT_ERROR/$PDBID.json
        if [ -f $RESULTF ]; then
            gzip -9 $RESULTF
        fi 
        mv $LOGF $OUT_LOG_FAILED 
        echo "$PDBID: FAILED" 
    fi
}
export -f process_pdb_id



START=`date +%s`

echo -----------------------------------------------------
# prosess all pdb codes in input dir in parallel with xargs
ls $INPUT | grep 'residues.csv$' | cut -c-4 | sort -u | xargs -P $THREADS -I {} bash -c "process_pdb_id {}"
echo -----------------------------------------------------

# error summary

SUMMARY="$OUT/summary.txt"
rm -f $SUMMARY
echo "OK: `ls $OUT_FUNPDBE | wc -l`" | tee -a $SUMMARY
echo "FAILED: `ls $OUT_LOG_FAILED | wc -l`" | tee -a $SUMMARY

echo "  Connection errors:    `find_errors 'requests.exceptions.ConnectionError'`" | tee -a $SUMMARY
echo "  Invalid schema:       `find_errors 'Invalid schema for'`" | tee -a $SUMMARY
echo "    Something is empty: `find_errors '\[\] is too short'`"    | tee -a $SUMMARY
echo "  Invalid residues:     `find_errors 'Invalid residues'`" | tee -a $SUMMARY
echo "    Complete mismatch:  `find_errors 'completely mismatched'`"    | tee -a $SUMMARY
echo "    AA mismatch:        `find_errors 'not match residue'`" | tee -a $SUMMARY


# collect error lines with details
grep "completely mismatched"                      -r $OUT_LOG_FAILED > $OUT/errors_numbering_mismatched.txt  # within Invalid residues 
grep "not match residue"                          -r $OUT_LOG_FAILED > $OUT/errors_mismatched_residue.txt    # within Invalid residues
grep "JSON does not comply with schema"           -r $OUT_LOG_FAILED > $OUT/errors_schema.txt


echo -----------------------------------------------------
END=`date +%s`
TIME=$((END-START))
echo OUTDIR: $OUT 
echo FINISHED IN `format_time TIME`
echo DONE.


