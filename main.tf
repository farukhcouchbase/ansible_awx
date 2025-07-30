resource "aws_instance" "test_server" {
  ami           = "ami-020cba7c55df1f615"
  instance_type = "t2.micro"
  key_name      = "worker-1"
  subnet_id     = "subnet-00c66667763e48ac7"

  tags = {
    Name = "ExampleWebAppServer"
  }
}


