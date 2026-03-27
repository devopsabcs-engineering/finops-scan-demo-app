docker build -t finops-demo-005 .
docker run -d -p 8085:80 --name finops-demo-005 finops-demo-005
Write-Host "FinOps Demo App 005 running at http://localhost:8085" -ForegroundColor Green
