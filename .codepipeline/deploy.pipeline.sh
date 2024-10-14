#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Example Usage:
# ./deploy-pipeline.sh --environment dev

display_flag_error() {
    echo "Error: Mandatory argument missing. Please provide the --environment flag." >&2
    exit 1
}

display_env_error() {
    echo "Error: Invalid environment. Please provide a valid value of [ dev | test | staging | prod ]" >&2
    exit 1
}

# Check if exactly two arguments are passed and the first one is --environment
if [[ "$#" -ne 2 ]] || [[ "$1" != --environment ]]; then
    display_flag_error
fi

# Validate environment argument using a case statement
case "$2" in
    "dev" | "test" | "staging" | "prod" )
        echo "[START] Pipeline deployment started at $(date '+%Y-%m-%d %H:%M') in the $2 environment."
        ;;
    * )
        display_env_error
        ;;
esac

# Define variables
APPLICATION_NAME=dialog-extream-batch
ENVIRONMENT_NAME=$2

DEPLOY_COMMAND="aws cloudformation deploy \
    --template-file pipeline.yml \
    --stack-name ${APPLICATION_NAME}-${ENVIRONMENT_NAME}-pipeline-stack \
    --parameter-overrides $(cat ${ENVIRONMENT_NAME}.parameters.properties)"

# For production, prompt for confirmation before proceeding
if [[ "$ENVIRONMENT_NAME" == "prod" ]]; then
    read -p "You are deploying this pipeline to prod. Are you sure? [y/n] " yn
    case $yn in
        [Yy]* ) eval $DEPLOY_COMMAND;;
        [Nn]* ) echo "Exiting."; exit 0;;
        * ) echo "Invalid option. Exiting."; exit 1;;
    esac
else
    eval $DEPLOY_COMMAND
fi