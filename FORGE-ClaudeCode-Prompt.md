# FORGE — Claude Code Build Prompt

> Copy everything below this line and send to Claude Code.

---

## PROJECT: FORGE — Framework Orchestrated Rewrite & Generation Engine

Build a production-ready multi-agent AI pipeline in Python that migrates enterprise J2EE applications from Struts 2.x to Spring MVC. The system uses LangGraph for agent orchestration, AWS Bedrock for LLM inference, AWS Bedrock Guardrails for content safety, DynamoDB for state management, and LiteLLM as the LLM provider abstraction layer.

---

## MISSION STATEMENT

FORGE is a multi-agent system with dual guardrails designed to modernise enterprise J2EE applications — orchestrating 15 specialised AI agents across a coordinated pipeline that systematically upgrades the full technology stack from Java source version to target version, Spring source version to target version, and eliminates Struts 2.x entirely, replacing every action class, OGNL expression, and struts.xml routing configuration with pure Spring MVC.

---

## TECH STACK

| Component | Technology | Purpose |
|---|---|---|
| Agent orchestration | LangGraph (Python) | Graph-based stateful pipeline, retry loops, conditional routing |
| LLM — transform + guardrails | Claude Sonnet 4.5 via AWS Bedrock | Code transformation and intelligent safety checks |
| LLM — review | Amazon Nova Pro via AWS Bedrock | Independent cross-model review |
| LLM abstraction | LiteLLM proxy | Swap LLM provider without code changes |
| Content safety | AWS Bedrock Guardrails (ApplyGuardrail API) | PII, sensitive data detection — standalone, not inline |
| State store | AWS DynamoDB | Per-file migration status, real-time progress |
| Manual review queue | AWS SQS | Decoupled queue for MANUAL files |
| Observability | LangSmith + AWS CloudWatch | Agent-level debug + pipeline metrics |
| RAG knowledge base | AWS Bedrock Knowledge Base | Coding standards, Spring migration patterns, ADRs |
| Config | agents.yaml | Which agents load per phase, model routing, thresholds |

---

## PROJECT STRUCTURE

```
forge/
├── migrate.py                    # CLI entry point
├── agents.yaml                   # Agent configuration
├── litellm-config.yaml           # LLM provider routing
├── requirements.txt
├── forge/
│   ├── __init__.py
│   ├── graph.py                  # LangGraph StateGraph definition
│   ├── state.py                  # TypedDict state schema
│   ├── config.py                 # Load agents.yaml, env vars
│   ├── agents/
│   │   ├── __init__.py
│   │   ├── base.py               # BaseAgent abstract class
│   │   ├── guardrails_pre.py     # Pre-transform guardrails agent
│   │   ├── guardrails_post.py    # Post-review guardrails agent
│   │   ├── leader.py             # Leader / orchestrator agent
│   │   ├── discovery.py          # Discovery agent
│   │   ├── risk_scorer.py        # Risk Scorer agent
│   │   ├── java_upgrade.py       # Java X→Y agent
│   │   ├── spring_upgrade.py     # Spring X→Y agent
│   │   ├── struts2_mvc.py        # Struts2→MVC elimination agent
│   │   ├── containerize.py       # Containerize agent
│   │   └── test_gen.py           # Test Gen agent
│   ├── review/
│   │   ├── __init__.py
│   │   ├── base_reviewer.py      # BaseReviewer abstract class
│   │   ├── java_reviewer.py
│   │   ├── spring_reviewer.py
│   │   ├── struts_reviewer.py
│   │   ├── container_reviewer.py
│   │   └── test_reviewer.py
│   ├── guardrails/
│   │   ├── __init__.py
│   │   └── bedrock_guardrails.py # ApplyGuardrail API wrapper
│   ├── state_store/
│   │   ├── __init__.py
│   │   └── dynamodb.py           # DynamoDB state manager
│   ├── queue/
│   │   ├── __init__.py
│   │   └── manual_queue.py       # SQS manual review queue
│   ├── manifest/
│   │   ├── __init__.py
│   │   └── migration_manifest.py # Manifest builder and reader
│   └── utils/
│       ├── __init__.py
│       ├── file_scanner.py       # Scan ./myapp/** 
│       ├── file_writer.py        # Write to ./migrated/myapp/
│       ├── context_builder.py    # Assemble context bundle per file
│       └── report.py             # migration-report.md generator
└── tests/
    ├── test_discovery.py
    ├── test_risk_scorer.py
    ├── test_struts2_mvc.py
    └── test_graph.py
```

---

## STATE SCHEMA — forge/state.py

```python
from typing import TypedDict, Optional, List, Literal
from dataclasses import dataclass, field

class FileStatus(TypedDict):
    file_path: str
    status: Literal["PENDING", "TRANSFORMING", "REVIEWING", "RETRY_1", "RETRY_2", "DONE", "MANUAL_REVIEW", "BLOCKED"]
    phase: str
    risk_tier: Literal["LOW", "MEDIUM", "HIGH", "UNSCORED"]
    risk_score: int
    transform_output: Optional[str]          # transformed source code
    review_score: Optional[int]              # 0-100 from Nova Pro
    review_verdict: Optional[Literal["PASS", "RETRY", "MANUAL"]]
    review_feedback: Optional[str]           # injected into retry
    guardrail_pre_verdict: Optional[Literal["PASS", "WARN", "BLOCK"]]
    guardrail_post_verdict: Optional[Literal["PASS", "WARN", "BLOCK"]]
    guardrail_findings: List[str]
    retry_count: int
    transform_model: str
    review_model: str
    error: Optional[str]

class ForgeState(TypedDict):
    # Current file being processed
    current_file: Optional[FileStatus]
    
    # Migration manifest (grows throughout run)
    manifest: dict                           # full manifest from discovery
    routing_map: dict                        # struts.xml parsed routes
    dependency_graph: dict                   # file dependency graph
    processing_order: List[str]              # topological sort result
    
    # Context bundle for current file
    context_bundle: dict                     # base class + DTO + linked JSPs
    
    # Phase configuration
    phase: str                               # discover/java21/spring6/struts/containerize/testgen
    dry_run: bool
    target_java_version: str
    target_spring_version: str
    source_dir: str                          # ./myapp/
    output_dir: str                          # ./migrated/myapp/
    
    # Run statistics
    files_processed: int
    files_passed: int
    files_retried: int
    files_manual: int
    files_blocked: int
    bedrock_calls: int
    estimated_cost_usd: float
    
    # Messages / routing signal
    next_action: Optional[str]
    messages: List[dict]
```

---

## LANGGRAPH PIPELINE — forge/graph.py

```python
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.dynamodb import DynamoDBSaver
from forge.state import ForgeState
from forge.agents import (
    guardrails_pre, leader, discovery, risk_scorer,
    java_upgrade, spring_upgrade, struts2_mvc,
    containerize, test_gen, guardrails_post
)
from forge.review import (
    java_reviewer, spring_reviewer, struts_reviewer,
    container_reviewer, test_reviewer
)

def route_after_guardrails_pre(state: ForgeState) -> str:
    verdict = state["current_file"]["guardrail_pre_verdict"]
    if verdict == "BLOCK":
        return "blocked"
    return "transform"

def route_after_review(state: ForgeState) -> str:
    verdict = state["current_file"]["review_verdict"]
    retry_count = state["current_file"]["retry_count"]
    if verdict == "PASS":
        return "guardrails_post"
    if verdict == "RETRY" and retry_count < 2:
        return "transform"          # retry with feedback injected
    return "manual_queue"           # MANUAL or retry limit exceeded

def route_after_guardrails_post(state: ForgeState) -> str:
    verdict = state["current_file"]["guardrail_post_verdict"]
    if verdict == "BLOCK":
        return "manual_queue"
    return "write_file"

def select_transform_agent(state: ForgeState) -> str:
    """Leader routes to the correct transform agent based on phase and file type."""
    phase = state["phase"]
    routing = {
        "discover":      "discovery",
        "java21":        "java_upgrade",
        "spring6":       "spring_upgrade",
        "struts":        "struts2_mvc",
        "containerize":  "containerize",
        "testgen":       "test_gen",
    }
    return routing.get(phase, "java_upgrade")

def select_review_agent(state: ForgeState) -> str:
    phase = state["phase"]
    routing = {
        "java21":       "java_reviewer",
        "spring6":      "spring_reviewer",
        "struts":       "struts_reviewer",
        "containerize": "container_reviewer",
        "testgen":      "test_reviewer",
    }
    return routing.get(phase, "java_reviewer")

def build_forge_graph(checkpointer=None):
    graph = StateGraph(ForgeState)
    
    # Register nodes
    graph.add_node("guardrails_pre",    guardrails_pre.run)
    graph.add_node("java_upgrade",      java_upgrade.run)
    graph.add_node("spring_upgrade",    spring_upgrade.run)
    graph.add_node("struts2_mvc",       struts2_mvc.run)
    graph.add_node("containerize",      containerize.run)
    graph.add_node("test_gen",          test_gen.run)
    graph.add_node("java_reviewer",     java_reviewer.run)
    graph.add_node("spring_reviewer",   spring_reviewer.run)
    graph.add_node("struts_reviewer",   struts_reviewer.run)
    graph.add_node("container_reviewer",container_reviewer.run)
    graph.add_node("test_reviewer",     test_reviewer.run)
    graph.add_node("guardrails_post",   guardrails_post.run)
    graph.add_node("write_file",        write_file_node)
    graph.add_node("manual_queue",      manual_queue_node)
    graph.add_node("blocked",           blocked_node)
    graph.add_node("update_state",      update_dynamodb_node)
    
    # Entry point
    graph.set_entry_point("guardrails_pre")
    
    # Guardrails pre → route to transform or blocked
    graph.add_conditional_edges(
        "guardrails_pre",
        route_after_guardrails_pre,
        {"transform": "java_upgrade", "blocked": "blocked"}  # overridden by leader
    )
    
    # All transform agents → correct review agent (via leader routing)
    for agent in ["java_upgrade","spring_upgrade","struts2_mvc","containerize","test_gen"]:
        graph.add_conditional_edges(agent, select_review_agent, {
            "java_reviewer":     "java_reviewer",
            "spring_reviewer":   "spring_reviewer",
            "struts_reviewer":   "struts_reviewer",
            "container_reviewer":"container_reviewer",
            "test_reviewer":     "test_reviewer",
        })
    
    # All review agents → route on verdict
    for reviewer in ["java_reviewer","spring_reviewer","struts_reviewer","container_reviewer","test_reviewer"]:
        graph.add_conditional_edges(reviewer, route_after_review, {
            "guardrails_post": "guardrails_post",
            "transform":       "struts2_mvc",  # overridden per phase
            "manual_queue":    "manual_queue",
        })
    
    # Post-review guardrails → write or manual
    graph.add_conditional_edges("guardrails_post", route_after_guardrails_post, {
        "write_file":   "write_file",
        "manual_queue": "manual_queue",
    })
    
    # Terminal nodes
    graph.add_edge("write_file",   "update_state")
    graph.add_edge("manual_queue", "update_state")
    graph.add_edge("blocked",      "update_state")
    graph.add_edge("update_state", END)
    
    return graph.compile(checkpointer=checkpointer)
```

---

## AGENT BASE CLASS — forge/agents/base.py

```python
from abc import ABC, abstractmethod
from langchain_aws import ChatBedrockConverse
from langchain_openai import ChatOpenAI
from langchain_core.tools import tool
from forge.state import ForgeState
from forge.config import Config
import boto3

class BaseAgent(ABC):
    """All 15 FORGE agents inherit from this. LLM is a swappable dependency."""
    
    def __init__(self, config: Config):
        self.config = config
        self.model = self._build_model(config.transform_model)
        self.bedrock_client = boto3.client("bedrock-runtime", region_name=config.aws_region)
    
    def _build_model(self, model_name: str):
        """LiteLLM proxy endpoint — swap Bedrock for internal LLM via config only."""
        if self.config.use_litellm_proxy:
            return ChatOpenAI(
                base_url=self.config.litellm_endpoint,
                api_key=self.config.litellm_api_key,
                model=model_name,
                temperature=0,
            )
        else:
            return ChatBedrockConverse(
                model=model_name,
                region_name=self.config.aws_region,
                temperature=0,
            )
    
    def apply_bedrock_guardrails(self, text: str, source: str = "INPUT") -> dict:
        """
        Standalone ApplyGuardrail API — works regardless of which LLM generated the text.
        source: "INPUT" (pre-transform check) or "OUTPUT" (post-review check)
        """
        response = self.bedrock_client.apply_guardrail(
            guardrailIdentifier=self.config.guardrail_id,
            guardrailVersion=self.config.guardrail_version,
            source=source,
            content=[{"text": {"text": text}}],
        )
        return {
            "action": response["action"],           # "NONE" or "GUARDRAIL_INTERVENED"
            "outputs": response.get("outputs", []),
            "assessments": response.get("assessments", []),
        }
    
    @abstractmethod
    def run(self, state: ForgeState) -> ForgeState:
        """Each agent implements its transformation logic here."""
        pass
    
    def build_prompt(self, state: ForgeState) -> str:
        """Assemble the context bundle prompt for this file."""
        file_status = state["current_file"]
        context = state["context_bundle"]
        
        prompt_parts = []
        
        # Routing context from struts.xml manifest
        if state.get("routing_map") and file_status["file_path"] in state["routing_map"]:
            routing = state["routing_map"][file_status["file_path"]]
            prompt_parts.append(f"[STRUTS ROUTING CONTEXT]\n{routing}")
        
        # Base class (already transformed)
        if context.get("base_class"):
            prompt_parts.append(f"[BASE CLASS — ALREADY TRANSFORMED]\n{context['base_class']}")
        
        # ActionForm DTO (already transformed)
        if context.get("action_form_dto"):
            prompt_parts.append(f"[ACTIONFORM DTO — ALREADY TRANSFORMED]\n{context['action_form_dto']}")
        
        # Linked JSPs (bundle together for tight coupling)
        if context.get("linked_jsps"):
            for jsp_path, jsp_content in context["linked_jsps"].items():
                prompt_parts.append(f"[LINKED JSP: {jsp_path}]\n{jsp_content}")
        
        # Review feedback (only on retry)
        if file_status.get("review_feedback") and file_status["retry_count"] > 0:
            prompt_parts.append(f"[REVIEW FEEDBACK FROM PREVIOUS ATTEMPT — FIX THESE ISSUES]\n{file_status['review_feedback']}")
        
        # The file to transform
        with open(file_status["file_path"], "r", encoding="utf-8", errors="replace") as f:
            source = f.read()
        prompt_parts.append(f"[TARGET FILE: {file_status['file_path']}]\n{source}")
        
        return "\n\n".join(prompt_parts)
```

---

## GUARDRAILS PRE AGENT — forge/agents/guardrails_pre.py

```python
from forge.state import ForgeState
from forge.agents.base import BaseAgent
from forge.config import Config

SYSTEM_PROMPT = """You are the FORGE Pre-Transform Guardrails Agent.
Analyse the provided source file and return a JSON verdict with these checks:

1. SECRET_SCAN: Scan for embedded passwords, AWS keys, API tokens, DB credentials in code/comments.
2. SCOPE_VALIDATOR: Confirm this file belongs to the agreed migration scope (correct package prefix).
3. PII_DETECTOR: Find PII patterns (emails, IDs, names) in code comments or string literals.
4. COMPLEXITY_GATE: Measure complexity (LOC, OGNL count, EJB refs). Block if exceeds threshold.

Return JSON:
{
  "verdict": "PASS" | "WARN" | "BLOCK",
  "findings": ["list of specific issues found"],
  "reason": "single sentence summary"
}

BLOCK if: secrets found, extreme complexity (>2000 LOC + >20 OGNL).
WARN if: PII detected, high complexity (warn but proceed).
PASS if: no issues."""

class GuardrailsPreAgent(BaseAgent):
    def run(self, state: ForgeState) -> ForgeState:
        file_status = state["current_file"]
        
        with open(file_status["file_path"], "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        
        # Step 1 — Bedrock Guardrails standalone check (classifiers, not LLM)
        bedrock_result = self.apply_bedrock_guardrails(content, source="INPUT")
        if bedrock_result["action"] == "GUARDRAIL_INTERVENED":
            state["current_file"]["guardrail_pre_verdict"] = "BLOCK"
            state["current_file"]["guardrail_findings"] = [
                f"Bedrock Guardrails: {a}" for a in bedrock_result["assessments"]
            ]
            state["current_file"]["status"] = "BLOCKED"
            return state
        
        # Step 2 — LLM-based intelligent checks (uses LiteLLM → Bedrock or internal)
        from langchain_core.messages import SystemMessage, HumanMessage
        response = self.model.invoke([
            SystemMessage(content=SYSTEM_PROMPT),
            HumanMessage(content=f"Analyse this file:\n\n{content[:8000]}")  # truncate for guardrails
        ])
        
        import json
        result = json.loads(response.content)
        
        state["current_file"]["guardrail_pre_verdict"] = result["verdict"]
        state["current_file"]["guardrail_findings"] = result.get("findings", [])
        
        if result["verdict"] == "BLOCK":
            state["current_file"]["status"] = "BLOCKED"
        
        return state

def run(state: ForgeState) -> ForgeState:
    from forge.config import get_config
    return GuardrailsPreAgent(get_config()).run(state)
```

---

## STRUTS2→MVC AGENT — forge/agents/struts2_mvc.py

```python
from forge.state import ForgeState
from forge.agents.base import BaseAgent

SYSTEM_PROMPT = """You are the FORGE Struts2→MVC Transform Agent.

Your job: eliminate every Struts 2 construct and replace with pure Spring MVC.

OUTPUT CONTRACT (verified by Guardrails Agent after you finish):
- Zero classes extending ActionSupport or Action
- Zero OGNL expressions (%{...}) in any file
- Zero struts.xml routing references
- Zero <s:> JSP tags
- Zero struts2-core dependency references

TRANSFORMATION RULES (apply in order):

RULE 1 — Class conversion:
- Remove: extends ActionSupport, implements ModelDriven<T>, implements Preparable
- Add: @Controller
- Add: @RequestMapping("{namespace}") — get namespace from [STRUTS ROUTING CONTEXT]
- If ModelDriven<T>: add @ModelAttribute method returning T instance
- If Preparable: merge prepare() logic into @ModelAttribute method

RULE 2 — Method conversion:
- public String execute() → map to method name from [STRUTS ROUTING CONTEXT]
- Determine HTTP method: GET if reads/displays, POST if saves/deletes/updates
- Map results: SUCCESS (dispatcher) → return "namespace/viewname"
- Map results: SUCCESS (redirectAction) → return "redirect:/target/path"
- Map results: INPUT → add if(bindingResult.hasErrors()) return "viewname";

RULE 3 — Field extraction to DTO:
- Collect all fields with getters/setters (OGNL-bound)
- Create XxxForm.java as @ModelAttribute class
- Convert validate() null checks → @NotBlank, @Size, @Min, @Max, @Email (JSR-380)
- If validate() calls DAO/service → keep business logic as Spring Validator bean, flag MANUAL

RULE 4 — JSP tag replacement:
- <s:form action="x"> → <form:form modelAttribute="xForm" action="x">
- <s:textfield name="f"> → <form:input path="f"/>
- <s:password name="p"> → <form:password path="p"/>
- <s:select name="s"> → <form:select path="s">
- <s:textarea name="t"> → <form:textarea path="t"/>
- <s:iterator value="%{list}"> → <c:forEach items="${list}" var="item">
- <s:if test="%{cond}"> → <c:if test="${cond}">
- <s:property value="%{x}"> → ${x}
- %{fieldName} → ${fieldName}
- OGNL static method %{@Class@method()} → FLAG MANUAL — no auto-conversion
- OGNL projection %{list.{field}} → FLAG MANUAL — move to controller
- OGNL selection %{list.{? cond}} → FLAG MANUAL — move to controller

RULE 5 — Interceptor mapping:
- Standard interceptor stack references → document in output, no code change needed
- Custom interceptor → generate HandlerInterceptor stub, register in WebMvcConfigurer
- Custom interceptor that calls invocation.getAction() → FLAG MANUAL

Return your response as JSON:
{
  "files": {
    "path/to/UserController.java": "full java source here",
    "path/to/UserForm.java": "full java source here",
    "path/to/views/user/list.jsp": "full jsp source here"
  },
  "manual_flags": [
    {"file": "path", "line": 47, "pattern": "OGNL projection", "reason": "..."}
  ],
  "webmvc_additions": ["interceptor registrations to add to WebMvcConfigurer"]
}"""

class Struts2MvcAgent(BaseAgent):
    def run(self, state: ForgeState) -> ForgeState:
        from langchain_core.messages import SystemMessage, HumanMessage
        import json
        
        state["current_file"]["status"] = "TRANSFORMING"
        state["current_file"]["transform_model"] = self.config.transform_model
        
        prompt = self.build_prompt(state)  # includes routing context + base class + JSPs + review feedback
        
        response = self.model.invoke([
            SystemMessage(content=SYSTEM_PROMPT),
            HumanMessage(content=prompt)
        ])
        
        result = json.loads(response.content)
        
        state["current_file"]["transform_output"] = json.dumps(result["files"])
        state["current_file"]["status"] = "REVIEWING"
        
        # Add MANUAL flags to findings
        if result.get("manual_flags"):
            existing = state["current_file"].get("guardrail_findings", [])
            state["current_file"]["guardrail_findings"] = existing + [
                f"MANUAL: {f['pattern']} in {f['file']} line {f.get('line','?')} — {f['reason']}"
                for f in result["manual_flags"]
            ]
        
        state["bedrock_calls"] += 1
        return state

def run(state: ForgeState) -> ForgeState:
    from forge.config import get_config
    return Struts2MvcAgent(get_config()).run(state)
```

---

## REVIEW AGENT BASE — forge/review/base_reviewer.py

```python
from forge.state import ForgeState
from forge.agents.base import BaseAgent

class BaseReviewer(BaseAgent):
    """Review agents use Amazon Nova Pro — different model family from transform agents."""
    
    def __init__(self, config):
        super().__init__(config)
        # Override: reviewers always use Nova Pro via LiteLLM
        self.model = self._build_model(config.review_model)
    
    def build_review_prompt(self, state: ForgeState, system_prompt: str) -> str:
        import json
        file_status = state["current_file"]
        
        original_path = file_status["file_path"]
        with open(original_path, "r", encoding="utf-8", errors="replace") as f:
            original = f.read()
        
        transformed = json.loads(file_status["transform_output"])
        transformed_str = json.dumps(transformed, indent=2)
        
        return f"""ORIGINAL SOURCE:
{original}

TRANSFORMED OUTPUT:
{transformed_str}

Review the transformation and return JSON:
{{
  "score": 0-100,
  "verdict": "PASS" | "RETRY" | "MANUAL",
  "feedback": "specific issues to fix on retry",
  "checks": {{"check_name": "PASS/FAIL"}}
}}

Score thresholds: PASS ≥ 80 | RETRY 50-79 | MANUAL < 50"""
    
    def run(self, state: ForgeState) -> ForgeState:
        from langchain_core.messages import SystemMessage, HumanMessage
        import json
        
        state["current_file"]["review_model"] = self.config.review_model
        
        response = self.model.invoke([
            SystemMessage(content=self.REVIEW_SYSTEM_PROMPT),
            HumanMessage(content=self.build_review_prompt(state, self.REVIEW_SYSTEM_PROMPT))
        ])
        
        result = json.loads(response.content)
        
        state["current_file"]["review_score"] = result["score"]
        state["current_file"]["review_verdict"] = result["verdict"]
        state["current_file"]["review_feedback"] = result.get("feedback", "")
        
        # Increment retry count if RETRY
        if result["verdict"] == "RETRY":
            state["current_file"]["retry_count"] += 1
        
        state["bedrock_calls"] += 1
        return state
```

---

## STRUTS REVIEWER — forge/review/struts_reviewer.py

```python
from forge.review.base_reviewer import BaseReviewer

class StrutsReviewer(BaseReviewer):
    REVIEW_SYSTEM_PROMPT = """You are the FORGE Struts Review Agent (Amazon Nova Pro).
    
You independently verify that the Struts 2.x elimination is complete and correct.

CHECK LIST (each scored independently):

1. ZERO_STRUTS_CLASSES (20 pts): No class extends ActionSupport, Action, or any Struts class.
2. ZERO_STRUTS_ROUTING (20 pts): No struts.xml references remain. Every route has @RequestMapping equivalent.
3. ZERO_OGNL (25 pts): Zero %{...} expressions in any JSP. Only ${} EL expressions.
4. ZERO_STRUTS_TAGS (20 pts): Zero <s:> tags. All replaced with <form:>, <c:>, or JSTL equivalents.
5. CORRECT_REDIRECTS (15 pts): SUCCESS(redirectAction) results correctly map to "redirect:/path".

SCORING:
- 100-80: PASS — transformation complete and correct
- 79-50:  RETRY — specific issues fixable by the transform agent
- 49-0:   MANUAL — fundamental issues requiring human review

Return JSON with score, verdict, feedback (specific issues for retry), and per-check results."""

def run(state):
    from forge.config import get_config
    return StrutsReviewer(get_config()).run(state)
```

---

## DYNAMODB STATE MANAGER — forge/state_store/dynamodb.py

```python
import boto3
import json
from datetime import datetime
from forge.state import FileStatus

class DynamoDBStateManager:
    """
    DynamoDB table: forge-migration-state
    Primary key: file_path (String)
    GSI: status-index on status attribute
    TTL: expires_at (Unix timestamp, 90 days)
    """
    
    def __init__(self, table_name: str, region: str):
        self.table = boto3.resource("dynamodb", region_name=region).Table(table_name)
    
    def put_file_status(self, file_status: FileStatus):
        item = {**file_status, "updated_at": datetime.utcnow().isoformat()}
        self.table.put_item(Item=item)
    
    def get_file_status(self, file_path: str) -> FileStatus | None:
        response = self.table.get_item(Key={"file_path": file_path})
        return response.get("Item")
    
    def get_files_by_status(self, status: str) -> list:
        response = self.table.query(
            IndexName="status-index",
            KeyConditionExpression="status = :s",
            ExpressionAttributeValues={":s": status}
        )
        return response.get("Items", [])
    
    def get_progress_summary(self) -> dict:
        statuses = ["PENDING","TRANSFORMING","REVIEWING","RETRY_1","RETRY_2","DONE","MANUAL_REVIEW","BLOCKED"]
        summary = {}
        for status in statuses:
            items = self.get_files_by_status(status)
            summary[status] = len(items)
        return summary
    
    def mark_pending(self, file_paths: list[str], phase: str):
        """Initialise all files for a phase as PENDING."""
        with self.table.batch_writer() as batch:
            for path in file_paths:
                batch.put_item(Item={
                    "file_path": path,
                    "status": "PENDING",
                    "phase": phase,
                    "risk_tier": "UNSCORED",
                    "risk_score": 0,
                    "retry_count": 0,
                    "guardrail_findings": [],
                    "updated_at": datetime.utcnow().isoformat()
                })
```

---

## BEDROCK GUARDRAILS WRAPPER — forge/guardrails/bedrock_guardrails.py

```python
import boto3
from typing import Literal

class BedrockGuardrails:
    """
    Standalone ApplyGuardrail API — works with ANY LLM output.
    Does NOT call a generative LLM. Uses AWS classifiers (NER, content filters).
    Data stays in your AWS region. No training on customer data.
    """
    
    def __init__(self, guardrail_id: str, guardrail_version: str, region: str):
        self.client = boto3.client("bedrock-runtime", region_name=region)
        self.guardrail_id = guardrail_id
        self.guardrail_version = guardrail_version
    
    def evaluate(
        self, 
        text: str, 
        source: Literal["INPUT", "OUTPUT"]
    ) -> dict:
        """
        Evaluate text against configured guardrail policies.
        source=INPUT: check before transformation (pre-transform)
        source=OUTPUT: check after transformation (post-review)
        
        Uses:
        - Sensitive info filters (NER classifier) — PII, credentials
        - Content filters (ML classifier) — harmful content categories
        - Topic denial (embedding classifier) — blocked topics
        - Word filters (exact match) — blocked keywords
        
        Does NOT use contextual grounding by default (unclear if uses generative model internally).
        """
        response = self.client.apply_guardrail(
            guardrailIdentifier=self.guardrail_id,
            guardrailVersion=self.guardrail_version,
            source=source,
            content=[{"text": {"text": text}}],
        )
        
        intervened = response["action"] == "GUARDRAIL_INTERVENED"
        
        findings = []
        for assessment in response.get("assessments", []):
            # Sensitive info findings
            for pii in assessment.get("sensitiveInformationPolicy", {}).get("piiEntities", []):
                if pii["action"] == "BLOCKED":
                    findings.append(f"PII detected: {pii['type']} — BLOCKED")
                else:
                    findings.append(f"PII detected: {pii['type']} — ANONYMIZED")
            
            # Content filter findings
            for cf in assessment.get("contentPolicy", {}).get("filters", []):
                if cf["action"] == "BLOCKED":
                    findings.append(f"Content filter: {cf['type']} confidence={cf['confidence']} — BLOCKED")
            
            # Topic denial findings
            for topic in assessment.get("topicPolicy", {}).get("topics", []):
                if topic["action"] == "BLOCKED":
                    findings.append(f"Denied topic: {topic['name']} — BLOCKED")
        
        return {
            "action": response["action"],       # "NONE" or "GUARDRAIL_INTERVENED"
            "intervened": intervened,
            "findings": findings,
            "outputs": response.get("outputs", []),
        }
```

---

## CLI ENTRY POINT — migrate.py

```python
#!/usr/bin/env python3
"""
FORGE — Framework Orchestrated Rewrite & Generation Engine
Usage:
  python migrate.py ./myapp --phase discover
  python migrate.py ./myapp --phase struts
  python migrate.py ./myapp --phase struts --dry-run
  python migrate.py ./myapp --phase struts --file src/main/java/com/corp/UserAction.java
  python migrate.py ./myapp --all-phases --resume
"""
import argparse
import sys
from forge.config import get_config
from forge.graph import build_forge_graph
from forge.manifest.migration_manifest import MigrationManifest
from forge.state_store.dynamodb import DynamoDBStateManager
from forge.utils.file_scanner import FileScanner
from forge.utils.report import generate_report
from langgraph.checkpoint.dynamodb import DynamoDBSaver

PHASES = ["discover", "java21", "spring6", "struts", "containerize", "testgen"]
HUMAN_GATES = ["struts", "containerize"]   # pause for engineer approval

def main():
    parser = argparse.ArgumentParser(description="FORGE migration pipeline")
    parser.add_argument("source_dir", help="Source directory (e.g. ./myapp)")
    parser.add_argument("--phase", choices=PHASES + ["all"], required=True)
    parser.add_argument("--dry-run", action="store_true", help="Full pipeline, no file writes")
    parser.add_argument("--resume", action="store_true", help="Skip DONE files, continue from last checkpoint")
    parser.add_argument("--file", help="Transform a single file only")
    parser.add_argument("--concurrency", type=int, default=1, help="Parallel file processing (default: 1)")
    parser.add_argument("--output-dir", default="./migrated", help="Output directory")
    args = parser.parse_args()
    
    config = get_config()
    state_manager = DynamoDBStateManager(config.dynamodb_table, config.aws_region)
    
    phases = PHASES if args.phase == "all" else [args.phase]
    
    for phase in phases:
        print(f"\n{'='*60}")
        print(f"  FORGE — Phase: {phase.upper()}")
        print(f"{'='*60}")
        
        # Human gate — pause for approval before risky phases
        if phase in HUMAN_GATES and not args.dry_run:
            response = input(f"\n[HUMAN GATE] About to run {phase} phase. Review migration-report.md first. Proceed? (yes/no): ")
            if response.lower() != "yes":
                print("Aborted by user.")
                sys.exit(0)
        
        # Discover phase — no Bedrock calls
        if phase == "discover":
            run_discovery(args, config, state_manager)
            continue
        
        # Get files to process
        if args.file:
            files = [args.file]
        elif args.resume:
            files = [f["file_path"] for f in state_manager.get_files_by_status("PENDING")]
        else:
            scanner = FileScanner(args.source_dir)
            files = scanner.get_files_for_phase(phase)
            state_manager.mark_pending(files, phase)
        
        print(f"  Files to process: {len(files)}")
        if args.dry_run:
            print("  DRY RUN — full pipeline, no file writes")
        
        # Build LangGraph with DynamoDB checkpointer
        checkpointer = DynamoDBSaver.from_conn_string(config.dynamodb_checkpoint_table)
        graph = build_forge_graph(checkpointer=checkpointer)
        
        # Process files
        for i, file_path in enumerate(files, 1):
            print(f"\n  [{i}/{len(files)}] {file_path}")
            
            # Skip if already DONE (resume mode)
            existing = state_manager.get_file_status(file_path)
            if existing and existing["status"] == "DONE" and args.resume:
                print(f"    → SKIP (already DONE)")
                continue
            
            initial_state = build_initial_state(file_path, phase, args, config)
            
            # Run the LangGraph pipeline for this file
            result = graph.invoke(
                initial_state,
                config={"configurable": {"thread_id": file_path}}
            )
            
            final_status = result["current_file"]["status"]
            score = result["current_file"].get("review_score", "—")
            print(f"    → {final_status} (score: {score})")
    
    # Generate report
    report_path = generate_report(state_manager, args.source_dir, args.dry_run)
    print(f"\n  Report: {report_path}")

def run_discovery(args, config, state_manager):
    from forge.agents.discovery import DiscoveryAgent
    from forge.agents.risk_scorer import RiskScorerAgent
    
    print("  Scanning codebase (no Bedrock calls)...")
    agent = DiscoveryAgent(config)
    manifest = agent.scan(args.source_dir)
    
    print("  Scoring risk...")
    scorer = RiskScorerAgent(config)
    manifest = scorer.score(manifest)
    
    manifest.save(f"{args.source_dir}/migration-manifest.json")
    generate_report(state_manager, args.source_dir, dry_run=False, manifest=manifest)
    print(f"  Discovery complete. {manifest.total_files} files found.")

def build_initial_state(file_path, phase, args, config) -> dict:
    from forge.utils.context_builder import ContextBuilder
    from forge.manifest.migration_manifest import MigrationManifest
    
    manifest = MigrationManifest.load(f"{args.source_dir}/migration-manifest.json")
    context = ContextBuilder(manifest).build(file_path)
    
    return {
        "current_file": {
            "file_path": file_path,
            "status": "PENDING",
            "phase": phase,
            "risk_tier": manifest.get_risk_tier(file_path),
            "risk_score": manifest.get_risk_score(file_path),
            "retry_count": 0,
            "guardrail_findings": [],
        },
        "manifest": manifest.to_dict(),
        "routing_map": manifest.routing_map,
        "dependency_graph": manifest.dependency_graph,
        "processing_order": manifest.processing_order,
        "context_bundle": context,
        "phase": phase,
        "dry_run": args.dry_run,
        "target_java_version": config.target_java_version,
        "target_spring_version": config.target_spring_version,
        "source_dir": args.source_dir,
        "output_dir": args.output_dir,
        "files_processed": 0,
        "files_passed": 0,
        "files_retried": 0,
        "files_manual": 0,
        "files_blocked": 0,
        "bedrock_calls": 0,
        "estimated_cost_usd": 0.0,
        "messages": [],
    }

if __name__ == "__main__":
    main()
```

---

## CONFIGURATION — agents.yaml

```yaml
forge:
  # LLM routing — change model names here to switch providers
  transform_model: "claude-sonnet-4-5"       # used by all transform agents
  review_model: "amazon.nova-pro-v1"          # used by all review agents
  guardrails_model: "claude-sonnet-4-5"       # used by Guardrails Agent LLM checks
  
  # LiteLLM proxy — set use_litellm_proxy: true to route via LiteLLM
  # When true: all model calls go to litellm_endpoint, Bedrock calls go to AWS directly
  use_litellm_proxy: false
  litellm_endpoint: "http://localhost:4000/v1"
  
  # AWS
  aws_region: "us-east-1"
  dynamodb_table: "forge-migration-state"
  dynamodb_checkpoint_table: "forge-langgraph-checkpoints"
  sqs_manual_queue_url: "https://sqs.us-east-1.amazonaws.com/123456789/forge-manual-review"
  
  # Bedrock Guardrails — standalone ApplyGuardrail API
  # Works regardless of which LLM is used for transformation
  guardrail_id: "your-guardrail-id"
  guardrail_version: "DRAFT"
  
  # Bedrock Knowledge Base (RAG)
  knowledge_base_id: "your-kb-id"
  
  # Migration targets (pluggable per project)
  source_java_version: "8"
  target_java_version: "21"
  source_spring_version: "5"
  target_spring_version: "6"
  
  # Risk thresholds
  complexity_block_threshold: 2000            # LOC — block if exceeded
  ognl_high_risk_threshold: 15               # OGNL expressions — HIGH risk
  manual_bypass_score: 90                    # Risk score — skip transform, go straight to manual
  
  # Review scoring
  pass_threshold: 80
  retry_threshold: 50
  max_retries: 2
  
  # Phases and human gates
  phases: ["discover", "java21", "spring6", "struts", "containerize", "testgen"]
  human_gates: ["struts", "containerize"]
  
  # Observability
  langsmith_project: "forge-migration"
  cloudwatch_namespace: "FORGE/Migration"
  
  # Agents loaded per phase (pluggable — add/remove agents here)
  phase_agents:
    discover:     ["discovery", "risk_scorer"]
    java21:       ["java_upgrade"]
    spring6:      ["spring_upgrade"]
    struts:       ["struts2_mvc"]
    containerize: ["containerize"]
    testgen:      ["test_gen"]
  
  # Review agents (always the same set)
  review_agents:
    java21:       "java_reviewer"
    spring6:      "spring_reviewer"
    struts:       "struts_reviewer"
    containerize: "container_reviewer"
    testgen:      "test_reviewer"
```

---

## LITELLM CONFIGURATION — litellm-config.yaml

```yaml
model_list:
  # Transform + Guardrails agents → Claude Sonnet via Bedrock (today)
  - model_name: claude-sonnet-4-5
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20251001
      aws_region_name: us-east-1

  # Review agents → Nova Pro via Bedrock (today)
  - model_name: amazon.nova-pro-v1
    litellm_params:
      model: bedrock/amazon.nova-pro-v1:0
      aws_region_name: us-east-1

  # Future: internal LLM (uncomment and update when ready)
  # - model_name: claude-sonnet-4-5      # same model name — FORGE agents unchanged
  #   litellm_params:
  #     model: openai/forge-migration-v1
  #     api_base: http://sagemaker-endpoint.internal/v1
  #     api_key: os.environ/INTERNAL_LLM_KEY

litellm_settings:
  drop_params: true
  num_retries: 3
  request_timeout: 120
  telemetry: false

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
```

---

## REQUIREMENTS — requirements.txt

```
langgraph>=0.2.0
langchain>=0.3.0
langchain-aws>=0.2.0
langchain-openai>=0.2.0
langsmith>=0.1.0
boto3>=1.35.0
botocore>=1.35.0
litellm>=1.50.0
pydantic>=2.0.0
pyyaml>=6.0
python-dotenv>=1.0.0
pytest>=8.0.0
pytest-asyncio>=0.23.0
```

---

## DYNAMODB TABLE DEFINITIONS — infrastructure/dynamodb.py

```python
"""
Run once to create DynamoDB tables.
python infrastructure/dynamodb.py
"""
import boto3

def create_tables(region="us-east-1"):
    dynamodb = boto3.client("dynamodb", region_name=region)
    
    # Migration state table
    dynamodb.create_table(
        TableName="forge-migration-state",
        KeySchema=[{"AttributeName": "file_path", "KeyType": "HASH"}],
        AttributeDefinitions=[
            {"AttributeName": "file_path", "AttributeType": "S"},
            {"AttributeName": "status",    "AttributeType": "S"},
            {"AttributeName": "phase",     "AttributeType": "S"},
        ],
        GlobalSecondaryIndexes=[
            {
                "IndexName": "status-index",
                "KeySchema": [
                    {"AttributeName": "status", "KeyType": "HASH"},
                    {"AttributeName": "phase",  "KeyType": "RANGE"},
                ],
                "Projection": {"ProjectionType": "ALL"},
            }
        ],
        BillingMode="PAY_PER_REQUEST",
        TimeToLiveSpecification={"Enabled": True, "AttributeName": "expires_at"},
    )
    print("Created: forge-migration-state")
    
    # LangGraph checkpoint table
    dynamodb.create_table(
        TableName="forge-langgraph-checkpoints",
        KeySchema=[
            {"AttributeName": "thread_id",      "KeyType": "HASH"},
            {"AttributeName": "checkpoint_id",  "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "thread_id",     "AttributeType": "S"},
            {"AttributeName": "checkpoint_id", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )
    print("Created: forge-langgraph-checkpoints")

if __name__ == "__main__":
    create_tables()
```

---

## ENVIRONMENT VARIABLES — .env.example

```bash
# AWS
AWS_REGION=us-east-1
AWS_PROFILE=forge-migration                  # or use access key + secret

# Bedrock Guardrails
FORGE_GUARDRAIL_ID=your-guardrail-id-here
FORGE_GUARDRAIL_VERSION=DRAFT

# Bedrock Knowledge Base
FORGE_KB_ID=your-knowledge-base-id-here

# LangSmith (agent-level debugging)
LANGCHAIN_TRACING_V2=true
LANGCHAIN_API_KEY=your-langsmith-key
LANGCHAIN_PROJECT=forge-migration

# LiteLLM (when using proxy)
LITELLM_MASTER_KEY=your-litellm-master-key
LITELLM_ENDPOINT=http://localhost:4000/v1

# Internal LLM (future — uncomment when ready)
# INTERNAL_LLM_KEY=your-internal-api-key
# INTERNAL_LLM_ENDPOINT=http://sagemaker-endpoint.internal/v1
```

---

## KEY IMPLEMENTATION NOTES FOR CLAUDE CODE

1. **Build all remaining agents** following the same pattern as `struts2_mvc.py` — each has a `SYSTEM_PROMPT` with specific rules and a `run(state)` function.

2. **Discovery agent** (`forge/agents/discovery.py`) must: walk the filesystem, classify each file by import analysis, build the dependency graph (extends/implements/JSP-links), detect Struts version, and produce a topological processing order.

3. **Context builder** (`forge/utils/context_builder.py`) must: for a given file, look up its dependencies in the manifest, load already-transformed versions from the output directory or DynamoDB, and bundle them with the routing manifest entry.

4. **struts.xml must be parsed FIRST** before any Java file is transformed. Add a `parse_struts_xml()` function that runs at the start of the struts phase and stores the routing map in the migration manifest.

5. **FileWriter** (`forge/utils/file_writer.py`) must: skip all writes if `dry_run=True`, otherwise write each file from the transform output JSON to `./migrated/myapp/`, preserving the package path structure.

6. **LangSmith** is enabled via environment variables only — no code change needed. Set `LANGCHAIN_TRACING_V2=true` and `LANGCHAIN_API_KEY` and every LangGraph node execution is automatically traced.

7. **Processing order for struts phase**: struts.xml → base action classes → ActionForm classes → interceptors → action classes (bundled with their JSPs) → standalone JSPs → WebMvcConfigurer.

8. **The `--resume` flag** works via LangGraph's DynamoDB checkpointer — the `thread_id` is the `file_path`, so each file's graph state is individually persisted and resumable.

9. **Bedrock Guardrails** uses the standalone `ApplyGuardrail` API — NOT inline with model invocation. This means it works identically when you switch to an internal LLM via LiteLLM.

10. **All agents inherit from `BaseAgent`** which uses `ChatOpenAI(base_url=litellm_endpoint)` when `use_litellm_proxy=true`, or `ChatBedrockConverse` directly when false. Switching LLM providers requires only changing `agents.yaml`.

---

*Generated by FORGE architecture design session. Build with Claude Code.*
