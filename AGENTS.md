# ALfit 역할과 공용 기록

- Claude는 구현·테스트·시뮬레이터 검증을 담당하고, Codex는 Product Integrity Reviewer로서 독립 감사와 공용 기준 문서 관리를 담당한다.
- 공용 정본은 C:\Users\kug02\codex-audit\records다. 기준 문서 갱신은 사용자가 지정한 이 Codex 대화가 담당한다. Claude는 별도 구현·실행 보고서를 남긴다.
- 먼저 공용 폴더의 ALfit_Product_Continuity_Index.md → ALfit_Product_Integrity_Master_Ledger (2).md → ALfit_Product_UX_Integrated_Master.md를 읽고, 현재 Phase의 최신 보고서·요청서와 README·통합지침을 확인한다. Ledger의 현재 실제 파일명에는 (2)가 포함된다. 저장소 안의 동명 문서를 공용 정본으로 혼동하지 않는다.
- 감사 전 실제 worktree 경로·HEAD·미커밋 변경과 보고 기준 리비전·소스 해시를 대조한다. 기존 Phase와 완료된 QA를 이어받고 새 Phase·전면 재감사·성공한 QA 반복을 임의로 시작하지 않는다.
- Codex는 앱 소스를 감사 목적으로 읽고 직접 구현하지 않는다. 보고와 코드·테스트·실행 증거를 대조하며 writer → state → readers → 권한·알림·후속 업무의 일관성을 확인한다.
- 상세 감사는 공용 폴더의 reports/<PhaseID>_audit_<차수>.md 또는 기존 보고 폴더에 남기고, 기준 문서는 Ledger → 관련 UX → Index 순서로 필요한 부분만 갱신한다. BLOCKER/CORRECTION/BACKLOG와 보고 사실·직접 확인·추정·미확인을 구분하며 CODE/RUNTIME/PRODUCT를 임의로 승격하지 않는다.
- 기존 CLAUDE.md의 프로젝트 지침, 확정 정책·HOLD, 과거 보고·미해결 항목을 보존한다. 사용자 요청에 따른 이 AGENTS.md의 역할·기록 경로 연결은 문서 작업이며 앱 구현 권한을 Codex에 추가하지 않는다.
- 2026-11-04 사용자 승인: 공용 records 폴더의 감사 기록 갱신은 매번 사용자에게 확인하지 않고 진행한다. 이 프로젝트의 .codex/config.toml에 records 추가 쓰기 범위와 auto_review를 설정한다. 호스트가 적용한 실제 권한과 자동 심사 결과를 준수하며 앱 소스 직접 구현 권한으로 확대하지 않는다.

## 전체 디자인 통일 · 사용자 선택 (2026-11-04)

- 요청 정본: C:\Users\kug02\codex-audit\records\ALfit_Design_Unification_Request_2026-11-04.md
- 선택 이미지: C:\Users\kug02\codex-audit\records\ALfit_Design_Concept_01.png — Claude도 두 파일을 실제 열고 확인한다.
- 계획/기준: 같은 records의 ALfit_Design_Unification_Plan_2026-11-04.md / ALfit_Design_Standards_2026-11-04.md. 단일 적용표는 ALfit_Design_Surface_Register.csv다.
- 첫 실행: records\requests\DU_implementation_1.md → DU_revalidation_1.md. 현재 .82의 증거·변경·원복 상태를 보존한 안정 지점에서 원본 확인 ACK 후 진행하며, 파일 게시만으로 상대 세션 실행을 가정하지 않는다.
- 전체 목록 → 공통 기준 → 실제 대표 화면 → 밀도 패턴/전체 확장 → 실제 화면 재검증. 세 시안 화면에 한정하지 않고 가입부터 근무·급여·정산까지 적용한다.
- 기존 전면 디자인 후속 제한은 사용자 승인 디자인 범위에서 대체한다. 실제 탭·정책·데이터/권한·검증 이력·HOLD·Android 금지 파일은 보존한다. Claude가 구현/기기 조작, 지정 Codex가 독립 감사/기준 기록을 담당한다. 공통 기준 문서의 별도 writer를 만들지 않는다.
