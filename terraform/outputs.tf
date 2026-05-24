output "nginx_public_ip" {
  description = "The public IP of the Nginx Gateway"
  value       = aws_instance.nginx.public_ip
}

output "nginx_public_dns" {
  description = "The public DNS of the Nginx Gateway"
  value       = aws_instance.nginx.public_dns
}

output "caller_private_ip" {
  description = "The private IP of the Caller worker"
  value       = aws_instance.caller.private_ip
}

output "inference_private_ip" {
  description = "The private IP of the Inference worker"
  value       = aws_instance.inference.private_ip
}

output "curl_test_command" {
  description = "Sample curl command to test end-to-end model inference via Nginx Gateway"
  value       = "curl -X POST http://${aws_instance.nginx.public_ip}/v1/chat/completions -H 'Content-Type: application/json' -d '{\"messages\": [{\"role\": \"user\", \"content\": \"Explain quantum computing in one short sentence.\"}]}'"
}
