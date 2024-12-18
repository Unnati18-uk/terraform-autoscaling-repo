output "aws_vpc_id" {
    value = aws_vpc.my_vpc.id
  
}
output "aws_load_balancer_dns" {
    value = aws_lb.my_alb.dns_name
  
}
