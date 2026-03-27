docker build -t finops-demo-001 .
docker run -d -p 8081:80 --name finops-demo-001 finops-demo-001
Write-Host "FinOps Demo App 001 running at http://localhost:8081" -ForegroundColor Green
