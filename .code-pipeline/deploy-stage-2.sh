#!/bin/bash
set -e  # Exit immediately if any command fails

echo "[START] Deployment started at $(date '+%Y-%m-%d %H:%M:%S')"

APPLICATION_NAME=
ENVIRONMENT_NAME=
JFROG_API_KEYWORD=
JFROG_API_KEY=
AWS_ACCOUNT_ID=

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
        --jfrog-password)
            JFROG_API_KEYWORD=$2
            shift ;;
        --jfrog-api-key)
            JFROG_API_KEY=$2
            shift ;;
        --aws-account)
            AWS_ACCOUNT_ID=$2
            shift;;
        --debug)
            DEBUG=$2
            shift ;;
        *)
            echo "$1 is not an option"
            exit 1 ;;
    esac
    shift
done

# Get AWS Account ID to determine environment
case "$AWS_ACCOUNT_ID" in
    "333333333333") ENVIRONMENT_NAME="dev" ;;  # Replace with your Dev AWS Account ID
    "111111111111") ENVIRONMENT_NAME="staging" ;;  # Replace with your Staging AWS Account ID
    "354918399435") ENVIRONMENT_NAME="prod" ;;  # Replace with your Prod AWS Account ID
    *)
        echo "ERROR: Unknown AWS account ID ($AWS_ACCOUNT_ID). Cannot determine environment."
        exit 1 ;;
esac

# JFrog Artifactory Details
JFROG_URL=${JFROG_URL:-"https://khalidallsha.jfrog.io/artifactory/lambda"}
JFROG_REPO=${JFROG_REPO:-"my-lambda-repo"}
JFROG_USER=${JFROG_USERNAME:-"tadipatriallisha@gmail.com"}
JFROG_API_KEY=${JFROG_API_KEY}

upload_to_jfrog() {
    local file_path=$1
    local lambda_name=$2
    local versioned_filename=""

    if [[ "$ENVIRONMENT_NAME" == "dev" ]]; then
        versioned_filename="${lambda_name}-d-latest.zip"
    else
        # Fetch latest version from JFrog for staging and prod
        local latest_version=$(curl -s -u "$JFROG_USER:$JFROG_API_KEY" \
            "${JFROG_URL}/${JFROG_REPO}/${ENVIRONMENT_NAME}/${lambda_name}/" | 
            grep -o "${lambda_name}-[sp]-[0-9]\+\.zip" |  # Extract matching filenames
            grep -o '[0-9]\+' |  # Extract version numbers
            sort -n | tail -n1)  # Get the highest version

        local new_version=1
        if [[ -n "$latest_version" ]]; then
            new_version=$((latest_version + 1))
        fi

        if [[ "$ENVIRONMENT_NAME" == "staging" ]]; then
            versioned_filename="${lambda_name}-s-${new_version}.zip"
        elif [[ "$ENVIRONMENT_NAME" == "prod" ]]; then
            versioned_filename="${lambda_name}-p-${new_version}.zip"  # Always 1 for prod
        fi
    fi

    #local upload_url="${JFROG_URL}/${JFROG_REPO}/${lambda_name}/${versioned_filename}"
    local upload_url="${JFROG_URL}/${JFROG_REPO}/${ENVIRONMENT_NAME}/${lambda_name}/${versioned_filename}"


    echo "Uploading $versioned_filename to JFrog at $upload_url"

    if [[ -z "$JFROG_USER" || -z "$JFROG_API_KEY" ]]; then
        echo "ERROR: JFrog credentials not found. Skipping JFrog upload."
        return 1
    fi

    # Upload file to JFrog
    if curl -v -u "$JFROG_USER:$JFROG_API_KEY" -T "$file_path" "$upload_url"; then
        echo "Upload successful: $versioned_filename"
    else
        echo "ERROR: Failed to upload $versioned_filename to JFrog."
        return 1
    fi
}

deploy_lambdas() {
    if [ -f "${DIR}/cloudformation.yml" ]; then
        LAMBDA_NAME=$(basename "$DIR")

        cd ${DIR}/dist
        zip -r "${LAMBDA_NAME}.zip" *
        mv "${LAMBDA_NAME}.zip" $OLDPWD && cd $OLDPWD

        # Upload to JFrog with Lambda Name
        upload_to_jfrog "${LAMBDA_NAME}.zip" "${LAMBDA_NAME}"
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
