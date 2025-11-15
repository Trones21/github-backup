# ---------- Config (override via env or CLI: `make deploy GITHUB_USERNAME=foo`) ----------

STACK_NAME                ?= github-backup-stack
REGION                    ?= us-east-1

GITHUB_USERNAME           ?= your-github-username
BACKUP_BUCKET             ?= your-backup-bucket-name
ARTIFACTS_BUCKET          ?= your-artifacts-bucket
LAMBDA_CODE_KEY           ?= github-backup/github-backup-lambda.zip

# Auth: use EITHER GitHubTokenSecretArn (recommended) or GitHubToken
# GitHubToken is usually only for testing or if you explicitly pass it in.
GITHUB_TOKEN              ?=
GITHUB_TOKEN_SECRET_ARN   ?=

# Behavior flags
INCLUDE_FORKS             ?= false
INCLUDE_ARCHIVED          ?= true
S3_PREFIX                 ?= github-backups

# Default schedule: 05:00 UTC on the 1st of each month
SCHEDULE_EXPR             ?= cron\(0 5 1 * ? *\)

# Packaging config
PACKAGE_DIR               ?= package
ZIP_FILE                  ?= github-backup-lambda.zip

# ---------- Targets ----------

.PHONY: package
package:
	rm -rf $(PACKAGE_DIR) $(ZIP_FILE)
	mkdir -p $(PACKAGE_DIR)
	pip install --target $(PACKAGE_DIR) requests
	cp lambda_function.py $(PACKAGE_DIR)/
	cd $(PACKAGE_DIR) && zip -r ../$(ZIP_FILE) .
	@echo "Built $(ZIP_FILE)"

.PHONY: upload
upload: package
	bash ./creds_get.sh
	aws s3 cp $(ZIP_FILE) s3://$(ARTIFACTS_BUCKET)/$(LAMBDA_CODE_KEY)
	bash ./creds_shred.sh
	@echo "Uploaded $(ZIP_FILE) to s3://$(ARTIFACTS_BUCKET)/$(LAMBDA_CODE_KEY)"

.PHONY: deploy
deploy: upload
	bash ./creds_get.sh
	@echo ">>> Optional: inspect creds (e.g. 'aws sts get-caller-identity --region $(REGION)') before deploy."
	aws cloudformation deploy \
	  --region $(REGION) \
	  --stack-name $(STACK_NAME) \
	  --template-file template.yaml \
	  --capabilities CAPABILITY_IAM \
	  --parameter-overrides \
	    GitHubUsername=$(GITHUB_USERNAME) \
	    BackupBucketName=$(BACKUP_BUCKET) \
	    S3Prefix=$(S3_PREFIX) \
	    IncludeForks=$(INCLUDE_FORKS) \
	    IncludeArchived=$(INCLUDE_ARCHIVED) \
	    GitHubToken=$(GITHUB_TOKEN) \
	    GitHubTokenSecretArn=$(GITHUB_TOKEN_SECRET_ARN) \
	    LambdaCodeS3Bucket=$(ARTIFACTS_BUCKET) \
	    LambdaCodeS3Key=$(LAMBDA_CODE_KEY) \
	    ScheduleExpression=$(SCHEDULE_EXPR)
	bash ./creds_shred.sh
	@echo "Deploy complete for stack $(STACK_NAME)"

.PHONY: delete
delete:
	bash ./creds_get.sh
	aws cloudformation delete-stack \
	  --region $(REGION) \
	  --stack-name $(STACK_NAME)
	bash ./creds_shred.sh
	@echo "Delete initiated for stack $(STACK_NAME)"

.PHONY: describe
describe:
	bash ./creds_get.sh
	aws cloudformation describe-stacks \
	  --region $(REGION) \
	  --stack-name $(STACK_NAME) \
	  --query "Stacks[0].{Status:StackStatus,Outputs:Outputs}" \
	  --output json
	bash ./creds_shred.sh

.PHONY: test-local
test-local:
	bash ./local_run.sh
