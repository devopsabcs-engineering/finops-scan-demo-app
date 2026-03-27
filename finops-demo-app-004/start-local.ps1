docker build -t finops-demo-004 .
docker run -d -p 8084:80 --name finops-demo-004 finops-demo-004
Write-Host "FinOps Demo App 004 running at http://localhost:8084" -ForegroundColor Green
