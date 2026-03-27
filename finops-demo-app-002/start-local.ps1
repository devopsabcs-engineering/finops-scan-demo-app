docker build -t finops-demo-002 .
docker run -d -p 8082:80 --name finops-demo-002 finops-demo-002
Write-Host "FinOps Demo App 002 running at http://localhost:8082" -ForegroundColor Green
