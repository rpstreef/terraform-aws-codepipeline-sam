# Terraform AWS CodePipeline for AWS SAM Applications

## About:

Deploys an AWS CodePipeline specifically designed for AWS SAM.

It requires these artifacts, amongst code obviously, in the source repository:
- AWS SAM template file (e.g. template.yaml), contains a description of your stack in CFL.
- CloudFormation Template configuration file (e.g. configuration.json), contains the parameter configuration you want to deploy your stack with. This is used during the CloudFormation Change Set, as part of the deployment stage.

## How to use:

This version of the module expects GitHub as source code repository to be used. You'll need an OAuthToken (``github_token``)  that has access to the repo (``github_repo``) you want to read from.

The ``stack_name`` is what you configured as a SAM stack name.

```hcl
module "codepipeline" {
  source = "github.com/rpstreef/terraform-aws-codepipeline-sam?ref=v1.0"

  resource_tag_name = var.resource_tag_name
  namespace         = var.namespace
  region            = var.region

  github_token        = var.github_token
  github_owner        = var.github_owner
  github_repo         = var.github_repo
  poll_source_changes = var.poll_source_changes

  build_image = "aws/codebuild/standard:4.0"

  stack_name = var.stack_name
}
```

## Changelog

### v1.0
 - Initial release