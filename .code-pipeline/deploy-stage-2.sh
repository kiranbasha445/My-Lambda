#!/bin/bash
set -e  # Exit immediately if any command fails

# Purpose:
# This script deploys the infrastructure common to all CIs.

# Arguments:
# Argument             Description
# ----------------------------------------------------
# application-name     Short name of the application
# environment-name     Short name for the environment, ex: tbv, stg, prod
# debug                Optional. true if you want to enable debug logging, false by default
# deployment-role-arn  Optional. Provide the IAM role to use for deployment. Useful for cross-account deployments.

# Example Usage:
# ./deploy-stage-2.sh --application-name infra-starter --environment-name tbv --debug true

echo "[START] Deployment started at $(date '+%Y-%m-%d %H:%M:%S')"

APPLICATION_NAME=
ENVIRONMENT_NAME=

DEBUG=false

while [ -n "$1" ]
do
    case "$1" in
        --application-name)
            APPLICATION_NAME=$2
            shift ;;
        --environment)
            ENVIRONMENT_NAME=$2
            shift ;;
        --debug)
            DEBUG=$2
            shift ;;
        *)
            echo "$1 is not an option"
            exit 1 ;;
    esac
    shift
done

$DEBUG && echo "DEBUG: APPLICATION_NAME: $APPLICATION_NAME"
$DEBUG && echo "DEBUG: ENVIRONMENT_NAME: $ENVIRONMENT_NAME"

PIPELINE_STACK_NAME="${APPLICATION_NAME}-${ENVIRONMENT_NAME}-pipeline-stack"
$DEBUG && echo "DEBUG: PIPELINE_STACK_NAME: $PIPELINE_STACK_NAME"

# Use GitHub Actions variables for the S3 path
GITHUB_RUN_ID=${GITHUB_RUN_ID:-"local-run"}
GITHUB_SHA=${GITHUB_SHA:-"local-sha"}

# Construct S3 path using GitHub Actions variables
S3_PATH="${APPLICATION_NAME}/${ENVIRONMENT_NAME}/${GITHUB_RUN_ID}/${GITHUB_SHA}"
$DEBUG && echo "DEBUG: S3_PATH: ${S3_PATH}"
BUILD_ARTIFACT_BUCKET_PATH=$(echo $S3_PATH | awk -F'/' '{print $1}')
$DEBUG && echo "DEBUG: BUILD_ARTIFACT_BUCKET_PATH=${BUILD_ARTIFACT_BUCKET_PATH}"
S3_PATH_TO_BUILD_ARTIFACT=$(echo $S3_PATH | grep -o '/.*[^/]')
$DEBUG && echo "DEBUG: S3_PATH_TO_BUILD_ARTIFACT=${S3_PATH_TO_BUILD_ARTIFACT}"
BUILD_ARTIFACT_NAME=$(echo $S3_PATH | awk -F '/' '{print $NF}')
$DEBUG && echo "DEBUG: BUILD_ARTIFACT_NAME=${BUILD_ARTIFACT_NAME}"

LAMBDA_CODE_ZIP_FILE_PATH="${S3_PATH_TO_BUILD_ARTIFACT}/lambdas"
$DEBUG && echo "DEBUG: LAMBDA_CODE_ZIP_FILE_PATH=${LAMBDA_CODE_ZIP_FILE_PATH}"
LAMBDA_CODE_ZIP_FILE_PATH_NO_LEADING_FORWARDSLASH=$(echo ${LAMBDA_CODE_ZIP_FILE_PATH} | sed 's,^/,,')
$DEBUG && echo "DEBUG: LAMBDA_CODE_ZIP_FILE_PATH_NO_LEADING_FORWARDSLASH=${LAMBDA_CODE_ZIP_FILE_PATH_NO_LEADING_FORWARDSLASH}"

deploy_lambdas() {
    $DEBUG && echo "DEBUG: deploy_lambdas $1"

    if [ -f "${DIR}/cloudformation.yml" ]
    then
        $DEBUG && echo "DEBUG: directory${DIR}"
        LAMBDA_NAME=$(basename $DIR)
        $DEBUG && echo "DEBUG: LAMBDA_NAME=${LAMBDA_NAME}"
        ZIPFILE="$(basename $DIR)_$(date +%s).zip"
        $DEBUG && echo "DEBUG: ZIPFILE=${ZIPFILE}"

        # Print the files in the current directory
        echo "Files in the current directory:"
        ls -al src/lambdas/CEDGCR/

        cd ${DIR}dist
        zip -r $ZIPFILE *
        mv $ZIPFILE $OLDPWD && cd $OLDPWD

        aws s3 cp ${ZIPFILE} s3://${BUILD_ARTIFACT_BUCKET_PATH}${LAMBDA_CODE_ZIP_FILE_PATH}/${ZIPFILE}

        aws cloudformation deploy \
            --stack-name ${APPLICATION_NAME}-${ENVIRONMENT_NAME}-${LAMBDA_NAME} \
            --template-file ${DIR}cloudformation.yml \
            --capabilities CAPABILITY_NAMED_IAM \
            --parameter-overrides \
            "ZippedLambdaS3Key=${LAMBDA_CODE_ZIP_FILE_PATH_NO_LEADING_FORWARDSLASH}/${ZIPFILE}" \
            "ArtifactsBucketName=${BUILD_ARTIFACT_BUCKET_PATH}"
            $(cat ${DIR}${ENVIRONMENT_NAME}.parameters.properties)
    fi
}

CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES=$(git diff --dirstat=files,0 HEAD~1 | grep 'src/shared' | sed 's/^.* * //')
$DEBUG && echo "DEBUG: CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES=${CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES}"

if [[ $CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES ]]
then
    echo "Detected changes in shared code, deploying all lambdas"
    ALL_LAMBDA_DIRECTORIES=$(ls -d -l "src/lambdas"/**/)
    for DIR in $ALL_LAMBDA_DIRECTORIES
    do
        deploy_lambdas $DIR
    done

    exit 0
fi

CHANGED_LAMBDA_DIRECTORIES=$(git diff --dirstat=files,0 HEAD~1 | grep src/lambdas | sed 's/^.* * //')
$DEBUG && echo "DEBUG: CHANGED_LAMBDA_DIRECTORIES=${CHANGED_LAMBDA_DIRECTORIES}"

if [[ $CHANGED_LAMBDA_DIRECTORIES ]]
then
    echo "Detected individual Lambda changes, deploying:"
    for DIR in $CHANGED_LAMBDA_DIRECTORIES
    do
        deploy_lambdas $DIR
    done

    exit 0
fi
