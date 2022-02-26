variable "public_subnet" {
  type    = list(string)
  default = ["10.0.4.0/24", "10.0.5.0/24"]
  }

variable "ingressrules" {
  type    = list(number)
  default = [80, 443, 22]
}

