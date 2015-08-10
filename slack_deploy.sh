#!/bin/bash

version="1.1"

function usage {
    echo "AWS Elastic Beanstalk Deployment Notifications for Slack (v${version})"
    echo
    echo "Usage: appsignal_deploy.sh -a <APP NAME> -c <SLACK CHANNEL> -w <WEBHOOK_URL> [options]"
    echo
    echo "Options:"
    echo
    echo "  -a  The name your the application in Elastic Beanstalk."
    echo "  -c  The channel to post to (without the hash)."
    echo "  -d  The name of the deployer (default: AWS Elastic Beanstalk)."
    echo "  -o  The Github Organization/user who owns the repo"
    echo "  -e  Error if the HTTP request fails. Note that this will abort the deployment."
    echo "  -h  Displays this help message."
    echo "  -q  Quiet mode."
    echo "  -v  Display version information."
    echo
}

function info {
    echo "[INFO] ${@}"
}

function warn {
    echo "[WARN] ${@}"
}

function error {
    echo "[ERROR] ${@}" >&2
    exit 1
}

app_name=""
channel=""
webhook_url=""
environment=$ENVIRONMENT
deployer=""
verbose=1
error_on_fail=0
branch=""
github_org=""

if [[ ${#} == 0 ]]; then
    usage
    exit 1
fi

while getopts "a:c:w:d:o:ehk:qv" option; do
    case "${option}" in
        a) app_name="${OPTARG}";;
        c) channel="${OPTARG}";;
        w) webhook_url="${OPTARG}";;
        d) deployer="${OPTARG}";;
        o) github_org="${OPTARG}";;
        e) error_on_fail=1;;
        h) usage; exit;;
        q) verbose=0;;
        v) echo "Version ${version}"; exit;;
        *) echo; usage; exit 1;;
    esac
done

if [[ -z "${app_name}" ]]; then
    error "The application name must be provided"
fi

if [[ -z "${channel}" ]]; then
    error "The channel must be provided"
fi

if [[ -z "${webhook_url}" ]]; then
    error "The webhook_url must be provided"
fi

if [[ -z "${deployer}" ]]; then
    deployer="AWS Elastic Beanstalk"
fi

if [[ -z "${github_org}" ]]; then
    error "github_org must be supplied"
fi

if [[ -f REVISION ]]; then
    archive_comment=$(cat REVISION)
else
    EB_CONFIG_SOURCE_BUNDLE=$(sudo /opt/elasticbeanstalk/bin/get-config container -k source_bundle)
    archive_comment=$(unzip -z "${EB_CONFIG_SOURCE_BUNDLE}" | tail -n1)

fi
if [[ -z "${archive_comment}" ]]; then
    archive_comment="unknown"
    error "Unable to extract application version from source REVISION file, or load version information from within the container"
else
    app_version=$(echo $archive_comment | cut -d: -f1)
    branch=$(echo $archive_comment | cut -d: -f2)
fi

if [[ -z "${environment}" ]]; then
  environment="development"
fi

if [[ ${verbose} == 1 ]]; then
    info "Application name: ${app_name}"
    info "Application version: ${app_version}"
    info "Application environment: ${environment}"
    info "Webhook URL: ${webhook_url}"
    info "Channel: ${channel}"
    info "Github Org: ${github_org}"
    info "Sending deployment notification..."
fi

http_response=$(curl -X POST -s -d "{\"channel\":\"#${channel}\",\
    \"text\":\"*${app_name} was successfully deployed to ${environment} by ${deployer}* :seedling:\",\
    \"username\":\"${deployer}\",\"attachments\":[\
        {\"fallback\":\"*${app_name} was successfully deployed to ${environment} by ${deployer}*\",\
        \"color\":\"#8eb573\",\"fields\":[\
            {\"title\":\"Environment:\",\"value\":\"${environment}\",\"short\":false},\
            {\"title\":\"Version:\",\"value\":\"<https://github.com/${github_org}/${app_name}/${app_version}|${app_version}>\"},\
            {\"title\":\"Branch:\",\"value\":\"${branch}\"}]}]}" "${webhook_url}")
http_status=$(echo "${http_response}" | head -n 1)
echo "${http_status}" | grep -q "ok"

if [[ ${?} == 0 ]]; then
    if [[ ${verbose} == 1 ]]; then
        info "Deployment notification successfully sent (${app_name} v${app_version})"
    fi
else
    msg="Failed to send deployment notification: ${http_status}"
    if [[ ${error_on_fail} == 1 ]]; then
        error "${msg}"
    else
        warn "${msg}"
    fi
fi
