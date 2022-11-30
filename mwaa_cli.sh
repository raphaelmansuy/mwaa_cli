#!/usr/bin/env bash
# A simple script to run the Airflow CLI on MWAA

# Author: Raphaël MANSUY
# Email: raphael.mansuy@elitizon.com
# Date: 2022-11-26
# License: MIT License

# This script requires; 

#    👉 jq to be installed on the host machine https://stedolan.github.io/jq/
#    👉  curl to be installed on the host machine https://curl.se/
#    👉 AWS CLI to be installed on the host machine https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html

# Usage: mwaa_cli.sh <command> <args>

# Examples:

# Example List all the dags and display with json format and jq
# 
# ./mwaa_cli.sh dags list --output json --region eu-west-1 --profile saml --environment airflow-v2 | jq 

# Example List all the dags and display with json format and jq and filter on a specific dag
# ./mwaa_cli.sh dags list --output json --region eu-west-1 --profile saml --environment airflow-v2 | jq '.[] | select(.dag_id == "my_dag")'

# Example List all the tasks of a dag and display with json format and jq and filter on paused == "False" 
# ./mwaa_cli.sh dags list --output json --region eu-west-1 --profile saml --environment airflow-v2 | jq '.[] | select(.paused == "False")'

# List all paused dags
# ./mwaa_cli.sh dags list --output json --region eu-west-1 --profile saml --environment airflow-v2 | jq -r '.[] | {dag_id: .dag_id,paused: .paused} | select (.paused == "True") | .dag_id' 

# List all dags that are not paused
# ./mwaa_cli.sh dags list --output json --region eu-west-1 --profile saml --environment airflow-v2 | jq -r '.[] | {dag_id: .dag_id,paused: .paused} | select (.paused == "False") | .dag_id'

# Reference of AirFlow commands https://airflow.apache.org/docs/apache-airflow/stable/cli-and-env-variables-ref.html#cli-commands

DISPLAY_ERROR="false"

ARGS="$*"

# the command to run
AIRFLOW_CMD=""

# get the name of the command
PROGRAM_NAME=$(basename $0)

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


log() { echo -e "$@" 1>&2; }

function displayUsage {
     # Progam name contains $0 with the path, so we need to remove the path
     PROMPT="${GREEN} > ${NC}"
     log "${BLUE}Usage: mwaa_cli.sh <command> <args>${NC} (<options>)"
     log ""
     log "Options:"
     log ""
     log "  -h, --help: Display this help"
     log "  -e, --environment: Set the MWAA environment name (default: ${MWAA_ENVIRONMENT})"
     log "  -r, --region: Set the AWS region (default: ${AWS_REGION})"
     log "  -p, --profile: Set the AWS CLI profile (default: ${PROFILE})"
     log ""
     log "Examples:"
     log ""
     log "${PROMPT} ${PROGRAM_NAME} dags list"
     log "${PROMPT} ${PROGRAM_NAME} dags list-runs -d <dag_id>"
     log "${PROMPT} ${PROGRAM_NAME} list_tasks <dag_id>"
     log "${PROMPT} ${PROGRAM_NAME} trigger_dag <dag_id>"
     log "${PROMPT} ${PROGRAM_NAME} dags pause <dag_id>"
     log "${PROMPT} ${PROGRAM_NAME} dags unpause <dag_id>"
     log ""
     log "Reference of AirFlow commands https://airflow.apache.org/docs/apache-airflow/stable/cli-and-env-variables-ref.html#cli-commands"
}

# Set the variable NEED_HELP to true if the first argument is -h or --help
NEED_HELP=false

# parse the command line

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            NEED_HELP=true
            shift # past argument
            ;;
        -p|--profile)
            PROFILE="$2"
            shift # past argument
            shift # past value
            ;;
        -r|--region)
            AWS_REGION=$2
            shift # past argument
            shift # past value
            ;;
        -e|--environment)
          MWAA_ENVIRONMENT=$2
          shift # past argument
          shift # past value
          ;;
        *)  # other arguments
            AIRFLOW_CMD="$AIRFLOW_CMD $1"
            shift # past argument
            ;;
    esac
done


# If the user needs help, display the usage
if [ "$NEED_HELP" = true ] ; then
    displayUsage
    exit 0
fi


# Check if user provided arguments
if [ "$AIRFLOW_CMD" = "" ]; then
     displayUsage
     log ""
     log "🔥 ${RED}Provide at least one argument to the Airflow CLI ${NC}";
     log ""
     exit 1;
fi


# Check if environment variable MWAA_ENVIRONMENT is provided
if [ "$MWAA_ENVIRONMENT" = "" ]; then
     displayUsage
     log ""
     log "🔥 ${RED}Provide the name of your environment in variable MWAA_ENVIRONMENT or with --environment option${NC}";
     log ""
     exit 1;
fi

# Check if environment variable AWS_REGION is provided
if [ "$AWS_REGION" = "" ]; then
     displayUsage
     log ""
     log "🔥 ${RED}Provide the region of your environment in variable AWS_REGION or with --region option${NC}";
     log ""
     exit 1;
fi

# Check if environment variable PROFILE is provided
if [ "$PROFILE" = "" ]; then
     displayUsage
     log ""
     log "🔥 ${RED}Provide the AWS CLI profile in variable PROFILE${NC} or with --profile option";
     log ""
     exit 1;
fi

# Cleaning the command
AIRFLOW_CMD=$(echo $AIRFLOW_CMD | sed 's/^ *//;s/ *$//')


# Running the command


log ""
log "🚀 ${GREEN}Airflow CLI command: \"${AIRFLOW_CMD}\" ${NC}"
log ""
log "  - Environment: ${MWAA_ENVIRONMENT}"
log "  - Region: ${AWS_REGION}"
log "  - Profile: ${PROFILE}"
log ""

# Terminal animation
log "⏳ ${BLUE}Running ...${NC}"
log ""


# Get CLI token and web server hostname from AWS MWAA CLI
CLI_JSON=$(aws mwaa create-cli-token --name $MWAA_ENVIRONMENT --region $AWS_REGION --profile $PROFILE)

# Parse results
CLI_TOKEN=$(echo $CLI_JSON | jq -r '.CliToken')
WEB_SERVER_HOSTNAME=$(echo $CLI_JSON | jq -r '.WebServerHostname')

# Trigger request of Airflow CLI from Amazon MWAA
RESPONSE=$(curl -s --request POST "https://$WEB_SERVER_HOSTNAME/aws_mwaa/cli" \
     --header "Authorization: Bearer $CLI_TOKEN" \
     --header "Content-Type: text/plain" \
     --data-raw "$AIRFLOW_CMD")

# Check if we have a valid JSON to be parsed...
if jq -e . >/dev/null 2>&1 <<<"$RESPONSE"; then
     # If JSON is valid then get stdout and stderr
     STDOUT=$(echo $RESPONSE | jq -r '.stdout')
     STDERR=$(echo $RESPONSE | jq -r '.stderr')

     # Decode the results from Base64
     echo $STDOUT | base64 -d 

     # If we have an error and DISPLAY_ERROR is true then display it
     if [ "$STDERR" != "" ] && [ "$DISPLAY_ERROR" = "true" ]; then
          # change the color of the text to red
          log "\033[0;31m" 
          log "Error:" 
          log $STDERR | base64 -d  
     fi
else
     # In case of invalid JSON just return the message to the terminal
     log $RESPONSE
fi
