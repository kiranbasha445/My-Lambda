#!/bin/bash
set -e  # Exit immediately if any command fails

echo "[START] Deployment started at $(date '+%Y-%m-%d %H:%M:%S')]"

APPLICATION_NAME=
ENVIRONMENT_NAME=
DEBUG=false

while [ -n "$1" ]; do
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

$DEBUG && echo "DEBUG: APPLICATION_NAME=${APPLICATION_NAME}"
$DEBUG && echo "DEBUG: ENVIRONMENT_NAME=${ENVIRONMENT_NAME}"

PIPELINE_STACK_NAME="${APPLICATION_NAME}-${ENVIRONMENT_NAME}-pipeline-stack"
$DEBUG && echo "DEBUG: PIPELINE_STACK_NAME=${PIPELINE_STACK_NAME}"

# GitHub Variables for S3 Path
GITHUB_RUN_ID=${GITHUB_RUN_ID:-"local-run"}
GITHUB_SHA=${GITHUB_SHA:-"local-sha"}

# S3 Upload Path
S3_PATH="${APPLICATION_NAME}/${ENVIRONMENT_NAME}/${GITHUB_RUN_ID}/${GITHUB_SHA}"
$DEBUG && echo "DEBUG: S3_PATH: ${S3_PATH}"
BUILD_ARTIFACT_BUCKET_PATH=$(echo $S3_PATH | awk -F'/' '{print $1}')
S3_PATH_TO_BUILD_ARTIFACT=$(echo $S3_PATH | grep -o '/.*[^/]')
BUILD_ARTIFACT_NAME=$(echo $S3_PATH | awk -F '/' '{print $NF}')

LAMBDA_CODE_ZIP_FILE_PATH="${S3_PATH_TO_BUILD_ARTIFACT}/lambdas"
LAMBDA_CODE_ZIP_FILE_PATH_NO_LEADING_FORWARDSLASH=$(echo ${LAMBDA_CODE_ZIP_FILE_PATH} | sed 's,^/,,')
$DEBUG && echo "DEBUG: LAMBDA_CODE_ZIP_FILE_PATH_NO_LEADING_FORWARDSLASH=${LAMBDA_CODE_ZIP_FILE_PATH_NO_LEADING_FORWARDSLASH"

# JFrog Artifactory Details
JFROG_URL=${JFROG_URL:-"https://khalidallsha.jfrog.io/ui/repos/tree/General"}
JFROG_REPO=${JFROG_REPO:-"my-lambda-repo"}
JFROG_USER=${JFROG_USERNAME:-"tadipatriallisha@gmail.com"}
JFROG_PASS=${JFROG_PASSWORD:-""}
JFROG_API_KEY=${JFROG_API_KEY:-""}

upload_to_jfrog() {
    local file_path=$1
    local file_name=$(basename "$file_path")

    $DEBUG && echo "DEBUG: Uploading $file_name to JFrog"

    if [[ -n "$JFROG_API_KEY" ]]; then
        curl -H "X-JFrog-Art-Api:$JFROG_API_KEY" \
             -T "$file_path" \
             "${JFROG_URL}/${JFROG_REPO}/${APPLICATION_NAME}/${ENVIRONMENT_NAME}/${GITHUB_RUN_ID}/${file_name}"
    elif [[ -n "$JFROG_USER" && -n "$JFROG_PASS" ]]; then
        curl -u "$JFROG_USER:$JFROG_PASS" \
             -T "$file_path" \
             "${JFROG_URL}/${JFROG_REPO}/${APPLICATION_NAME}/${ENVIRONMENT_NAME}/${GITHUB_RUN_ID}/${file_name}"
    else
        echo "ERROR: JFrog credentials not found. Skipping JFrog upload."
    fi
}

deploy_lambdas() {
    $DEBUG && echo "DEBUG: deploy_lambdas $1"

    if [ -f "${DIR}/cloudformation.yml" ]; then
        $DEBUG && echo "DEBUG: directory ${DIR}"
        LAMBDA_NAME=$(basename $DIR)
        $DEBUG && echo "DEBUG: LAMBDA_NAME=${LAMBDA_NAME}"
        ZIPFILE="$(basename $DIR)_$(date +%s).zip"
        $DEBUG && echo "DEBUG: ZIPFILE=${ZIPFILE}"
        echo "Files in the current directory:"
        ls -al src/lambdas/CEDGCR/

        cd ${DIR}/dist
        zip -r $ZIPFILE *
        mv $ZIPFILE $OLDPWD && cd $OLDPWD

        # Upload to S3
        aws s3 cp "${ZIPFILE}" "s3://${BUILD_ARTIFACT_BUCKET_PATH}${LAMBDA_CODE_ZIP_FILE_PATH}/${ZIPFILE}"

        # Upload to JFrog
        upload_to_jfrog "${ZIPFILE}"
    fi
}

CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES=$(git diff --dirstat=files,0 HEAD~1 | grep 'src/shared' | sed 's/^.* * //')
$DEBUG && echo "DEBUG: CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES=${CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES}"

if [[ $CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES ]]; then
    echo "Detected changes in shared code, deploying all lambdas"
    ALL_LAMBDA_DIRECTORIES=$(ls -d -l "src/lambdas"/**/)
    for DIR in $ALL_LAMBDA_DIRECTORIES; do
        deploy_lambdas "$DIR"
    done

    exit 0
fi

CHANGED_LAMBDA_DIRECTORIES=$(git diff --dirstat=files,0 HEAD~1 | grep src/lambdas | sed 's/^.* * //')
$DEBUG && echo "DEBUG: CHANGED_LAMBDA_DIRECTORIES=${CHANGED_LAMBDA_DIRECTORIES}"

if [[ $CHANGED_LAMBDA_DIRECTORIES ]]; then
    echo "Detected individual Lambda changes, deploying:"
    for DIR in $CHANGED_LAMBDA_DIRECTORIES; do
        deploy_lambdas "$DIR"
    done

    exit 0
fi
