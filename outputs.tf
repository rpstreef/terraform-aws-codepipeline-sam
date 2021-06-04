locals {
  o_codepipeline = try(aws_codepipeline._[0], {})

  o_codebuild = try(aws_codebuild_project._[0], {})
}

output "codepipeline" {
  description = "The full `aws_codepipeline` object."
  value       = local.o_codepipeline
}

output "codebuild" {
  description = "The full `aws_codebuild_project` object."
  value       = local.o_codebuild
}