#!/bin/bash
set -e  # Exit immediately if any command fails

echo "[START] Deployment started at $(date '+%Y-%m-%d %H:%M:%S')"

# Define variables
APPLICATION_NAME=
ENVIRONMENT_NAME=
JFROG_API_KEYWORD=
JFROG_API_KEY=
AWS_ACCOUNT_ID=
DEBUG=false

# Parse command-line arguments
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
            echo "ERROR: $1 is not a valid option."
            exit 1 ;;
    esac
    shift
done

# Determine environment based on AWS Account ID
case "$AWS_ACCOUNT_ID" in
    "333333333333") ENVIRONMENT_NAME="dev" ;;  # Dev AWS Account ID
    "354918399435") ENVIRONMENT_NAME="staging" ;;  # Staging AWS Account ID
    "333333333333") ENVIRONMENT_NAME="prod" ;;  # Prod AWS Account ID (Duplicate Account ID, check this!)
    *)
        echo "ERROR: Unknown AWS account ID ($AWS_ACCOUNT_ID). Cannot determine environment."
        exit 1 ;;
esac

# Set JFrog Artifactory details
JFROG_URL=${JFROG_URL:-"https://khalidallsha.jfrog.io/artifactory/lambda"}
JFROG_REPO=${JFROG_REPO:-"my-lambda-repo"}

# Fetch JFrog credentials from AWS Secrets Manager
echo "Fetching JFrog credentials from AWS Secrets Manager..."
JFROG_USER=$(aws secretsmanager get-secret-value --secret-id dev/my-lambda-repo/jfrog/jfroguserid --query SecretString --output text | jq -r '.JFROG_USER')
JFROG_API_KEY=$(aws secretsmanager get-secret-value --secret-id dev/my-lambda-repo/jfrog/jfrogapikey --query SecretString --output text | jq -r '.JFROG_API_KEY')

# Ensure JFrog API key is retrieved successfully
if [[ -z "$JFROG_API_KEY" ]]; then
    echo "ERROR: Failed to fetch JFROG_API_KEY from AWS Secrets Manager."
    exit 1
fi

# Function to upload Lambda zip files to JFrog
upload_to_jfrog() {
    local file_path=$1
    local lambda_name=$2
    local versioned_filename=""

    echo "Preparing to upload ${lambda_name} to JFrog..."
    
    # Determine versioning for JFrog artifacts
    if [[ "$ENVIRONMENT_NAME" == "dev" ]]; then
        versioned_filename="${lambda_name}-d-latest.zip"
    else
        echo "Fetching latest version for $lambda_name from JFrog..."
        local latest_version=$(curl -s -u "$JFROG_USER:$JFROG_API_KEY" \
            "${JFROG_URL}/${JFROG_REPO}/${ENVIRONMENT_NAME}/${lambda_name}/" | \
            grep -o "${lambda_name}-[sp]-[0-9]\+\.zip" | \
            grep -o '[0-9]\+' | \
            sort -n | tail -n1)

        local new_version=1
        if [[ -n "$latest_version" ]]; then
            new_version=$((latest_version + 1))
        fi

        if [[ "$ENVIRONMENT_NAME" == "staging" ]]; then
            versioned_filename="${lambda_name}-s-${new_version}.zip"
        elif [[ "$ENVIRONMENT_NAME" == "prod" ]]; then
            versioned_filename="${lambda_name}-p-${new_version}.zip"
        fi
    fi

    local upload_url="${JFROG_URL}/${JFROG_REPO}/${ENVIRONMENT_NAME}/${lambda_name}/${versioned_filename}"

    echo "Uploading $versioned_filename to JFrog at $upload_url..."
    
    # Check for missing credentials
    if [[ -z "$JFROG_USER" || -z "$JFROG_API_KEY" ]]; then
        echo "ERROR: JFrog credentials not found. Skipping JFrog upload."
        return 1
    fi

    # Perform file upload
    if curl -v -u "$JFROG_USER:$JFROG_API_KEY" -T "$file_path" "$upload_url"; then
        echo "Upload successful: $versioned_filename"
    else
        echo "ERROR: Failed to upload $versioned_filename to JFrog."
        return 1
    fi
}

# Function to deploy individual Lambda functions
deploy_lambdas() {
    if [ -f "${DIR}/index.ts" ]; then
        LAMBDA_NAME=$(basename "$DIR")
        
        echo "Zipping and preparing $LAMBDA_NAME for upload..."
        
        cd ${DIR}/dist
        zip -r "${LAMBDA_NAME}.zip" *
        mv "${LAMBDA_NAME}.zip" $OLDPWD && cd $OLDPWD

        # Upload to JFrog
        upload_to_jfrog "${LAMBDA_NAME}.zip" "${LAMBDA_NAME}"
    fi
}

# Detect changes in shared Lambda code
CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES=$(git diff --dirstat=files,0 HEAD~1 | grep 'src/shared' | sed 's/^.* * //')
$DEBUG && echo "DEBUG: CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES=${CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES}"

if [[ $CHANGED_SHARED_LAMBDA_CODE_DIRECTORIES ]]
then
    echo "Detected changes in shared code, deploying all Lambdas..."
    ALL_LAMBDA_DIRECTORIES=$(ls -d -l "src/lambdas"/**/)
    for DIR in $ALL_LAMBDA_DIRECTORIES
    do
        deploy_lambdas $DIR
    done
    exit 0
fi

# Detect changes in individual Lambda directories
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

echo "No changes detected. Deployment completed successfully."
