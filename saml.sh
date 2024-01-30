# Assuming you have the SAML assertion and the ARNs for the provider and role
SAML_ASSERTION=$(echo "BASE64_ENCODED_SAML_ASSERTION" | base64 -d)

# Use the assertion to assume a role using AWS STS
ASSUME_ROLE_OUTPUT=$(aws sts assume-role-with-saml --role-arn "arn:aws:iam::AWS_ACCOUNT_ID:role/ROLE_NAME" --principal-arn "arn:aws:iam::AWS_ACCOUNT_ID:saml-provider/PROVIDER_NAME" --saml-assertion "$SAML_ASSERTION")

# Extract temporary security credentials
AWS_ACCESS_KEY_ID=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.AccessKeyId')
AWS_SECRET_ACCESS_KEY=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.SecretAccessKey')
AWS_SESSION_TOKEN=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.SessionToken')

# Configure AWS CLI with temporary credentials
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set aws_session_token "$AWS_SESSION_TOKEN"





#!/bin/bash

# Function to decode and parse SAML assertion to list roles
function parse_saml_assertion() {
    echo "Decoding SAML Assertion..."
    # Replace this with the command or method you use to obtain your SAML assertion
    SAML_ASSERTION=$(get_saml_assertion_command)

    # Decode the SAML assertion and extract available roles
    echo "Extracting available roles from SAML Assertion..."
    ROLES=$(echo $SAML_ASSERTION | base64 --decode | grep 'Role=' | awk -F, '{print $2}' | awk -F/ '{print $NF}')
    
    echo "Available Roles:"
    echo "$ROLES"
}

# Function to assume a role using SAML
function assume_role_with_saml() {
    read -p "Enter the Role Name you wish to assume: " ROLE_NAME
    PRINCIPAL_ARN="arn:aws:iam::AWS_ACCOUNT_ID:saml-provider/YOUR_SAML_PROVIDER"
    ROLE_ARN="arn:aws:iam::AWS_ACCOUNT_ID:role/${ROLE_NAME}"

    # Assume the selected role
    echo "Assuming role: $ROLE_NAME"
    CREDENTIALS=$(aws sts assume-role-with-saml --role-arn "$ROLE_ARN" --principal-arn "$PRINCIPAL_ARN" --saml-assertion "$SAML_ASSERTION" --duration-seconds 3600)

    # Extract and export temporary credentials
    export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.Credentials.SessionToken')

    echo "Credentials set for role: $ROLE_NAME"
}

# Main script starts here
parse_saml_assertion
assume_role_with_saml

# Your AWS CLI command here, e.g., aws s3 ls
