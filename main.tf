locals {
  resource_name = "${var.environment}-${var.resource_tag_name}"

  tags = {
    Environment = var.environment
    Name        = var.resource_tag_name
  }
  
}

# -----------------------------------------------------------------------------
# Resources: Random string
# -----------------------------------------------------------------------------
resource "random_string" "postfix" {
  count = var.codepipeline_sam_module_enabled ? 1 : 0

  length  = 6
  number  = false
  upper   = false
  special = false
  lower   = true
}

# -----------------------------------------------------------------------------
# Resources: CodePipeline
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "artifact_store" {
  count = var.codepipeline_sam_module_enabled ? 1 : 0

  bucket        = "${local.resource_name}-codepipeline-artifacts-${one(random_string.postfix.*.result)}"
  acl           = "private"
  force_destroy = true

  lifecycle_rule {
    enabled = true

    expiration {
      days = 5
    }
  }
}

module "iam_codepipeline" {
  source = "github.com/rpstreef/tf-iam?ref=v1.2"

  environment       = var.environment
  region            = var.region
  resource_tag_name = var.resource_tag_name

  iam_module_enabled = var.codepipeline_sam_module_enabled

  assume_role_policy = file("${path.module}/policies/codepipeline-assume-role.json")
  template           = file("${path.module}/policies/codepipeline-policy.json")
  role_name          = "codepipeline-role"
  policy_name        = "codepipeline-policy"

  role_vars = {
    codebuild_project_arn = try(one(aws_codebuild_project._.*.arn), "")
    s3_bucket_arn         = try(one(aws_s3_bucket.artifact_store.*.arn), "")
  }
}

module "iam_cloudformation" {
  source = "github.com/rpstreef/tf-iam?ref=v1.2"

  environment       = var.environment
  region            = var.region
  resource_tag_name = var.resource_tag_name

  iam_module_enabled = var.codepipeline_sam_module_enabled

  assume_role_policy = file("${path.module}/policies/cloudformation-assume-role.json")
  template           = file("${path.module}/policies/cloudformation-policy.json")
  role_name          = "cloudformation-role"
  policy_name        = "cloudformation-policy"

  role_vars = {
    s3_bucket_arn         = try(one(aws_s3_bucket.artifact_store.*.arn), "")
    codepipeline_role_arn = try(module.iam_codepipeline.role_arn, "")
  }
}

resource "aws_codepipeline" "_" {
  count = var.codepipeline_sam_module_enabled ? 1 : 0

  name     = "${local.resource_name}-codepipeline"
  role_arn = try(module.iam_codepipeline.role_arn, "")

  artifact_store {
    location = one(aws_s3_bucket.artifact_store.*.bucket)
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source"]

      configuration = {
        OAuthToken           = var.github_token
        Owner                = var.github_owner
        Repo                 = var.github_repo
        Branch               = var.github_branch
        PollForSourceChanges = var.poll_source_changes
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source"]
      output_artifacts = ["build"]

      configuration = {
        ProjectName = one(aws_codebuild_project._.*.name)
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "CreateChangeSet"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CloudFormation"
      input_artifacts = ["build"]
      role_arn        = try(module.iam_cloudformation.role_arn, "")
      version         = 1
      run_order       = 1

      configuration = {
        ActionMode            = "CHANGE_SET_REPLACE"
        Capabilities          = "CAPABILITY_IAM,CAPABILITY_AUTO_EXPAND"
        OutputFileName        = "ChangeSetOutput.json"
        RoleArn               = try(module.iam_cloudformation.role_arn, "")
        StackName             = var.stack_name
        TemplatePath          = "build::packaged.yaml"
        ChangeSetName         = "${var.stack_name}-deploy"
        TemplateConfiguration = "build::configuration.json"
      }
    }

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CloudFormation"
      input_artifacts = ["build"]
      version         = 1
      run_order       = 2

      configuration = {
        ActionMode     = "CHANGE_SET_EXECUTE"
        Capabilities   = "CAPABILITY_IAM,CAPABILITY_AUTO_EXPAND"
        OutputFileName = "ChangeSetExecuteOutput.json"
        StackName      = var.stack_name
        ChangeSetName  = "${var.stack_name}-deploy"
      }
    }
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [stage[0].action[0].configuration]
  }
}

# -----------------------------------------------------------------------------
# Resources: CodeBuild
# -----------------------------------------------------------------------------
module "iam_codebuild" {
  source = "github.com/rpstreef/tf-iam?ref=v1.2"

  environment       = var.environment
  region            = var.region
  resource_tag_name = var.resource_tag_name

  iam_module_enabled = var.codepipeline_sam_module_enabled

  assume_role_policy = file("${path.module}/policies/codebuild-assume-role.json")
  template           = file("${path.module}/policies/codebuild-policy.json")
  role_name          = "codebuild-role"
  policy_name        = "codebuild-policy"

  role_vars = {
    s3_bucket_arn = try(one(aws_s3_bucket.artifact_store.*.arn), "")
  }
}

resource "aws_codebuild_project" "_" {
  count = var.codepipeline_sam_module_enabled ? 1 : 0

  name          = "${local.resource_name}-codebuild"
  description   = "${local.resource_name}_codebuild_project"
  build_timeout = var.build_timeout
  badge_enabled = var.badge_enabled
  service_role  = try(module.iam_codebuild.role_arn, "")

  artifacts {
    type           = "CODEPIPELINE"
    namespace_type = "BUILD_ID"
    packaging      = "ZIP"
  }

  environment {
    compute_type    = var.build_compute_type
    image           = var.build_image
    type            = "LINUX_CONTAINER"
    privileged_mode = var.privileged_mode

    environment_variable {
      name  = "ARTIFACT_BUCKET"
      value = one(aws_s3_bucket.artifact_store.*.bucket)
    }

    dynamic "environment_variable" {
      for_each = var.environment_variable_map

      content {
        name  = environment_variable.value.name
        value = environment_variable.value.value
        type  = environment_variable.value.type
      }
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = var.buildspec
  }

  tags = local.tags
}
