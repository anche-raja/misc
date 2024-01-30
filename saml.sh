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
