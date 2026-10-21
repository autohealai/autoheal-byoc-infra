#!/usr/bin/env bash
#
# bootstrap-state-aws.sh: create the S3 remote-state bucket for a BYOC install.
#
# Terragrunt stores its state in an S3 bucket, but Terraform cannot create the
# bucket that holds its own state (chicken-and-egg). Run this ONCE, with AWS
# credentials for the install account, before `terragrunt init`. It is
# idempotent: re-running against an existing bucket only re-applies its
# settings, so it is safe to retry.
#
# Usage:
#   ./scripts/bootstrap-state-aws.sh \
#     --bucket acme-autoheal-tfstate \
#     --region us-west-2 \
#     [--kms-key-arn arn:aws:kms:us-west-2:111111111111:key/...]
#
# The bucket and region must match the remote_state config block in your
# root.hcl (examples/aws/root.hcl). That block sets use_lockfile = true, so state
# locking uses a lock object in the same bucket and no DynamoDB table is needed.
#
# The bucket gets versioning (state history, a cheap guard against a bad apply),
# default encryption (SSE-KMS with --kms-key-arn, else SSE-S3), all public access
# blocked, ACLs off, and a policy that denies requests without TLS.

set -euo pipefail

BUCKET=""
REGION=""
KMS_KEY_ARN=""

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)      BUCKET="$2"; shift 2 ;;
    --region)      REGION="$2"; shift 2 ;;
    --kms-key-arn) KMS_KEY_ARN="$2"; shift 2 ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "unknown argument: $1" ;;
  esac
done

[[ -n "$BUCKET" ]] || die "--bucket is required"
[[ -n "$REGION" ]] || die "--region is required"

# Bucket names are a global namespace: 3-63 chars, lowercase letters, digits,
# dots and hyphens. Catch the bad name here instead of in a failed API call.
if ! [[ "$BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
  die "bucket '$BUCKET' is invalid: 3-63 lowercase letters, digits, dots or hyphens"
fi

command -v aws >/dev/null || die "aws CLI not found on PATH"

CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text)" \
  || die "no AWS credentials; sign in to the install account first"
PARTITION="$(cut -d: -f2 <<<"$CALLER_ARN")"
ACCOUNT="$(cut -d: -f5 <<<"$CALLER_ARN")"
echo "==> account $ACCOUNT, region $REGION"

# 1. Bucket -------------------------------------------------------------------
# head-bucket returns 403 for a bucket another account owns.
if aws s3api head-bucket --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT" 2>/dev/null; then
  echo "==> bucket $BUCKET already exists"
  LOCATION="$(aws s3api get-bucket-location --bucket "$BUCKET" --query LocationConstraint --output text)"
  [[ "$LOCATION" == "None" ]] && LOCATION="us-east-1"
  [[ "$LOCATION" == "$REGION" ]] || die "bucket $BUCKET is in $LOCATION, not $REGION"
else
  echo "==> creating bucket $BUCKET"
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" --object-ownership BucketOwnerEnforced >/dev/null \
      || die "cannot create bucket $BUCKET; the name may be taken in another account"
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" --object-ownership BucketOwnerEnforced \
      --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null \
      || die "cannot create bucket $BUCKET; the name may be taken in another account"
  fi
fi

# 2. Settings -------------------------------------------------------------------
echo "==> blocking public access"
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "==> turning on versioning"
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled

if [[ -n "$KMS_KEY_ARN" ]]; then
  echo "==> default encryption SSE-KMS with $KMS_KEY_ARN"
  ENCRYPTION="{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"aws:kms\",\"KMSMasterKeyID\":\"$KMS_KEY_ARN\"},\"BucketKeyEnabled\":true}]}"
else
  echo "==> default encryption SSE-S3"
  ENCRYPTION='{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
fi
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration "$ENCRYPTION"

echo "==> denying requests without TLS"
POLICY="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"DenyInsecureTransport\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:*\",\"Resource\":[\"arn:$PARTITION:s3:::$BUCKET\",\"arn:$PARTITION:s3:::$BUCKET/*\"],\"Condition\":{\"Bool\":{\"aws:SecureTransport\":\"false\"}}}]}"
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$POLICY"

# Old state versions are kept 90 days, enough to roll back a bad apply.
echo "==> expiring old state versions after 90 days"
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --lifecycle-configuration \
  '{"Rules":[{"ID":"expire-old-state-versions","Status":"Enabled","Filter":{},"NoncurrentVersionExpiration":{"NoncurrentDays":90},"AbortIncompleteMultipartUpload":{"DaysAfterInitiation":7}}]}'

cat <<DONE

State backend ready. Put these in the remote_state config block of root.hcl:

  bucket = "$BUCKET"
  region = "$REGION"

A pipeline identity other than you needs s3:ListBucket on the bucket and
s3:GetObject, s3:PutObject and s3:DeleteObject on its objects$( [[ -n "$KMS_KEY_ARN" ]] && echo ", plus kms:Encrypt, kms:Decrypt and kms:GenerateDataKey on the key" ).

Next, from your copy of examples/aws:
  cd prod/infra && terragrunt plan
DONE
