namespace = "ecommerce" # Harbor 프로젝트 이름과 동일 (지은님 CI/CD 답변 기준). 메인 ecr_namespace와 같게
# Jenkins가 같은 이미지를 Harbor와 ECR에 같은 이름·태그로 push한다. web은 프론트엔드
repositories         = ["auth", "product", "order", "promotion", "web"]
image_tag_mutability = "IMMUTABLE"
keep_image_count     = 10 # push 순서 기준. 롤백할 버전은 최근 10번 안에 있어야 함
force_delete         = false
