# 🛠️ AWS S3 Publish Logs

Uploads logs from archive folder into AWS S3 bucket. Logs are gzipped before
upload.

## Usage Example

An example workflow step using this action:

<!-- markdownlint-disable MD013 -->
```yaml
- name: AWS S3 Publish Logs
  uses: fdio/.github/.github/actions/aws-s3-publish-logs@master
```
<!-- markdownlint-enable MD013 -->

## Inputs

<!-- markdownlint-disable MD013 -->

| Variable Name         | Description                                                   |
| --------------------- | ------------------------------------------------------------- |
| aws_access_key_id     | Unique, public identifier for an AWS IAM user.                |
| aws_secret_access_key | Long-term security credential for AWS account or an IAM user. |
| aws_region            | AWS region for S3 bucket.                                     |
| s3_bucket             | Name of the Amazon S3 bucket.                                 |
| s3_path               | Path within Amazon AWS S3 bucket.                             |
| archives_path         | Source directory with logs artifact to archive.               |

<!-- markdownlint-enable MD013 -->

## Requirements/Dependencies

The gzip command-line tool must be available in the environment for the action
to succeed.