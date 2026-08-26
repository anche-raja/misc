# Detailed Prompt: Replicate the "AMS Internal Asset Management" Java Application

Use this document as a build prompt/spec to recreate an equivalent Java application with the **same tech stack, same library versions, and same architecture** as the original system. GitLab/CI configuration is intentionally excluded — this covers only the application itself.

---

## 1. High-Level Architecture

Build a **legacy-style Java EE / Spring / Struts2 hybrid web application**, packaged as a **WAR** (optionally wrapped in an **EAR**), deployed to **WebSphere Liberty**. It is NOT a Spring Boot application — there is no embedded server, no fat jar, no `@SpringBootApplication`. Bootstrap is entirely `web.xml`-driven.

Key architectural facts to reproduce:
- **Two parallel web frameworks coexist**: Apache **Struts 2** handles almost all functional endpoints (via `StrutsPrepareAndExecuteFilter` mapped to `/*`); Spring MVC's `DispatcherServlet` is mounted only at `/ams/*` and hosts exactly **one** `@Controller` — a global error-page controller. There are **zero** `@RestController` classes.
- **No ORM.** Persistence is 100% **Spring JDBC** (`NamedParameterJdbcTemplate` + hand-written Oracle SQL + manual `RowMapper<T>` implementations). No JPA, no Hibernate, no `.hbm.xml`, no `@Entity`.
- **No Lombok.** All domain POJOs have hand-written getters/setters, `implements Serializable`, explicit `serialVersionUID`.
- Authentication is **pre-authenticated SSO via reverse-proxy headers** (IBM WebSEAL pattern: `iv-user` / `iv-groups` headers), not a login form. Authorization is fine-grained role-per-permission (~50 `SecurityRoleType` constants like `INT_SEARCH_ASSETS`, `INT_CANCEL_ORDER`).
- Domain objects carry real business logic (not pure data holders) — e.g. `Asset.isCanDecommission()`, `Order.getInstallLeadTimeDays()`.
- A legacy "typesafe enum" pattern is used instead of Java `enum`: abstract `LoadableType` base class (code/description/databaseId) with `public static final` singleton subclass instances registered in a `LinkedHashMap`.

### Multi-module layout (Maven reactor)

Reproduce as **three separate Maven "repos"/reactors** (or three top-level aggregator directories if using one repo):

```
ams-parent-bom/                     (parent POM + BOM, packaging=pom)
ams-common/                         (shared library, packaging=pom, aggregator)
├── AssetManagementNetworkValidation    (jar)
├── AssetManagementSharedCommon         (jar)
└── AssetManagementSharedServices       (jar)
ams-internal/                       (main application, packaging=pom, aggregator)
├── AssetManagementInternalCommon       (jar)
├── AssetManagementInternalServices     (jar)
├── AssetManagementInternalWeb          (war)
└── AssetManagementInternalEar          (ear)
```

Use a placeholder groupId such as `com.example.ams` (pick any groupId your organization prefers — this is just a placeholder).

---

## 2. Exact Dependency & Plugin Versions (Maven, from parent BOM)

Java: **1.8** (`maven.compiler.source` / `target` = 1.8; no separate compiler-plugin version override was pinned — just rely on the default properties, or explicitly set `maven-compiler-plugin` to a version compatible with Java 8).

| Component | Artifact | Version |
|---|---|---|
| Struts2 | `org.apache.struts:struts2-core` | **6.8.0** |
| Struts2 plugins | `struts2-json-plugin`, `struts2-spring-plugin`, `struts2-convention-plugin` | **6.8.0** |
| OGNL (Struts2 dep) | `ognl:ognl` | **3.3.5** |
| Commons Text (Struts2 dep) | `org.apache.commons:commons-text` | **1.12.0** |
| FreeMarker (Struts2 dep) | `org.freemarker:freemarker` | **2.3.33** |
| Spring Framework | `spring-core/context/context-support/beans/jdbc/tx/web/webmvc` | **5.3.39** |
| Spring Security | `spring-security-core/config/web/taglibs` | **5.3.13.RELEASE** |
| Spring Security OAuth2 | `org.springframework.security.oauth:spring-security-oauth2` | **2.5.2.RELEASE** |
| Log4j2 | `log4j-core`, `log4j-api`, `log4j-slf4j-impl` | **2.26.0** |
| Jackson | `com.fasterxml.jackson.core:jackson-databind` | **2.20.2** |
| Servlet API | `javax.servlet:javax.servlet-api` (provided) | **3.1.0** |
| JSTL | `jstl:jstl` (runtime) | **1.2** |
| Oracle JDBC | `com.oracle.database.jdbc:ojdbc8` | **12.2.0.1** (test scope in BOM); runtime image uses **ojdbc8-21.5.0.0.jar** bundled directly as a shared library, not pulled from Maven Central |
| Commons Lang3 | `org.apache.commons:commons-lang3` | **3.17.0** |
| Commons Lang (legacy) | `commons-lang:commons-lang` | **2.5** |
| Commons IO | `commons-io:commons-io` | **2.17.0** |
| Commons Collections4 | `org.apache.commons:commons-collections4` | **4.5.0** |
| Commons Validator | `commons-validator:commons-validator` | **1.4.0** |
| json-lib | `net.sf.json-lib:json-lib` (classifier `jdk15`) | **2.4** |
| ezmorph | `net.sf.ezmorph:ezmorph` | **1.0.6** |
| H2 (test only) | `com.h2database:h2` | **1.3.176** |
| AspectJ | `org.aspectj:aspectjtools` | **1.7.4** |
| JUnit | `junit:junit` | **4.12** |
| Mockito | `org.mockito:mockito-all` | **1.9.5** |
| JaCoCo plugin | `org.jacoco:jacoco-maven-plugin` | **0.8.5** |
| maven-war-plugin | | **2.6** |
| maven-ear-plugin | | **2.8** |
| wildfly-maven-plugin (unused legacy leftover, `local` profile only) | | **2.0.2.Final** |
| buildnumber-maven-plugin | | **1.3** |
| Checkstyle plugin | | **2.15** (Puppycrawl checkstyle **5.6**) |

No `.mvn/`, `mvnw`, or `maven-wrapper.properties` exist — Maven version is whatever is installed locally (Maven 3.x, compatible with the above plugin versions).

**Deliberately absent** (do not add): Lombok, Hibernate/JPA, Velocity, Displaytag, Spring Boot (any `spring-boot-*` artifact), any embedded servlet container dependency.

---

## 3. Runtime / Deployment Stack

- **App server**: WebSphere Liberty (base image family `websphere-liberty:26.0.0.2-full-java8-openj9-ubi-minimal`), Java 8 (OpenJ9).
- **Liberty features**: `mpMetrics-1.1`, `servlet-3.1`, `jsp-2.3`, `jdbc-4.1`, `transportSecurity-1.0`, `ssl-1.0`, `mpHealth-4.0`.
- **HTTP ports**: 9081 (HTTP), 9444 (HTTPS, TLSv1.2).
- **Application deployment**: WAR only in practice (`AssetManagementInternalWeb.war`) with context-root `AssetManagementInternalWeb`; the EAR module exists in the build (packaging pattern) but the Dockerfile deploys the WAR directly.
- **Database**: Oracle, connected via JNDI `jdbc/amsInternalDS`, connection pool name `amsInternalDS`, driver `oracle.jdbc.pool.OracleDataSource`, TCPS protocol, `SSL_SERVER_DN_MATCH=NO`. Table naming convention: prefix `AMS_*` (e.g. `AMS_ASSETS`, `AMS_ORDERS`, `AMS_CUSTOMER_SCHEDULES`, `AMS_SAVE_FOR_LATER`), sequences like `AMS_ASSET_RETURNS_SQ`, package-qualified stored procedures like `AMS_NCR_SCHEDULING_PG.schedule_site_type_ncr`.
- **Logging**: Log4j2, console + rolling file appenders under `${sys:AppLogDir}` (`debug.log`, size+time-based rollover, 90-day retention), a dedicated `ALERT_LOGGER` (error-only rolling file appender for infra alerting), and an `APP_VERSION_LOGGER`. Pattern: `%d{ISO8601} AMS-INT %-5p [%l] %m%n`.
- JVM options set via Liberty `jvm.options`: `-DAppLogDir=...`, `-Dspring.profiles.active=<env>` (profiles: `local`, `was`/production, `qa`, `fit` referenced in security config).

Build a Dockerfile that layers Liberty config (`server.xml`, `jvm.options`, `bootstrap.properties`), copies the Oracle JDBC jar into `/config/configDropins/`, imports internal CA certs into the JVM cacerts truststore, and copies the built WAR into `/config/apps/`.

---

## 4. `ams-common` Module — Shared Domain Library

### AssetManagementSharedCommon (`org.example.am.shared.domain`)
Plain POJO domain model, ~100 classes. Base classes:
- `BaseDomain` (abstract): `createdDate`, `modifiedDate`, `createdByContact`, `modifiedByContact`, `currentTime` — audit fields, extended by `Asset`, `Order`, `NetworkChangeRequest`.
- `LoadableType` (abstract, "typesafe enum" base): `code`, `description`, `databaseId`; subclasses register static singleton instances in a `LinkedHashMap<String,X>` (e.g. `AssetType.VPN`, `.VPN_61E`, `.VPN_NIT`, `.LEGACY_VPN`).

Representative domain classes to recreate with realistic fields and embedded business-rule methods:
- `Asset extends BaseDomain` — `assetType`, `assetId`, `assetTag`, `serialNumber`, nested `Installation`, `Address installationAddress`, `Contact`, `AssetConfiguration`, `MaintenanceWindow`, `Order`, `AssetStatusType`, `NetworkChangeRequest`, self-ref `replacementAsset`, `Decommission`, `Customer`. Methods: `isCanDecommission()`, `isCanMove()`, `isCanModifyConfig()`, `setInactivePortConfigurationTypesToAuto()`, `clearAllMacAddresses()`.
- `Order extends BaseDomain` — `Asset`, `Address shippingAddress`, 3x `Contact`, `OrderStatusType`, `ShippingCarrier`, `DueDiligence`. Methods: `getInstallLeadTimeDays()`, `isMigrateOrder()`, `getAssetProblemForMigratingOrder()`.
- `Customer` (no BaseDomain) — collections of `Asset`, `AmsService`, `Contact`, `Event`; `TechLine`; `Address`; `CustomerEarlyAdopter`.
- `Rma` — flat POJO: serials, tracking number, `ShippingCarrier`, `RmaStatusType`, dates, reason.
- `NetworkChangeRequest extends BaseDomain` — mirrors Order's shipping/install/contact triad, `Set<NetworkChangeRequestType>`, `Timeslot moveTimeslot`, `DueDiligence`.
- `Address` — `addressLine1/2`, `city`, `zipCode`, `county`, `StateType state`, `CountryType country`; `toString()` builds a formatted mailing address.
- ~40 "type" classes following the `LoadableType` pattern: `AssetStatusType`, `OrderStatusType`, `OrderType`, `RmaStatusType`, `NetworkChangeRequestStatusType`, `NetworkChangeRequestType`, `AssetConfigurationStatusType`, `AssetConfigurationType`, `AssetProblemType`, `EventType`, `ServiceStatusType`, `ServiceType`, `PortConfigurationType`, `CountryType`, `StateType`, `DayType`, `HourType`, `PropertyType`, `SearchCriteriaType`, `QueueStatusType`, `EmailQueueStatusType`, `EmailTemplateType`, `EmailEntityType`, `HelpCenterDocumentType/LinkType/TagType`, `SaveForLaterType`, `AddressType`, `ContactType`, `AssetActionType`, `EntityActionEnum`, `DecommissionStatusType`, `NetworkConfigurationType`, `InstallationStatusType`, `ETLStatus`, `DisplayStatusType`, `DataSourceType`, `FacilitationCallType`.
- Comparators (`org.example.am.shared.domain.comparator`): `CountryComparator`, `AssetComparator`, `EventComparator`, `LegacyAssetTagComparator`, `LoadableValuesComparator`, `StateComparator`.

Dependencies: `log4j-api`, `ezmorph`, `commons-validator`.

### AssetManagementNetworkValidation (`org.example.am.network`)
- `domain`: `IPRange`, `RestrictedIPRanges`.
- `validation`: `LanTypeAValidator`, `LanTypeBValidator`, `LanTypeCValidator`, `LanValidator`, `WanValidator`, `NetworkUtils` — IP/subnet validation logic for asset network configs, each with a matching JUnit4 test.

Depends on `AssetManagementSharedCommon` + `commons-lang`.

### AssetManagementSharedServices (`org.example.am.shared`)
Service + DAO layer shared across internal/external apps. No `src/main/resources` — all wiring via `@Component`/`@Service`/`@Repository` + `@Autowired` (component-scanned), no Spring XML.

- `dao` (interfaces) / `dao.impl` (`@Repository("name")` impls) — `BaseDAO` holds a `NamedParameterJdbcTemplate` (injected via `@Autowired setDataSource(DataSource)`). DAOs: `AddressDAO`, `AdministrationDAO`, `CalendarDAO`, `ConfigDAO`, `ContactDAO`, `CustomerDAO`, `CustomerSearchDAO`, `AssetAttentionDAO`, `AssetConfigDAO`, `AssetDAO`, `AssetProblemDAO`, `AssetSearchDAO`, `EmailDetailDAO`, `EmergencyReplacementDAO`, `InstallationCalendarDAO`, `MaintenanceWindowDAO`, `ModifyConfigurationDAO`, `ModifyQueueDAO`, `NetworkChangeRequestDAO`, `OrderDAO`, `PreLoadServiceDAO`, `RequestDAO`, `RmaDAO`, `SaveForLaterDAO`, `ScheduleServiceDAO`, `StoredProcedureDAO`, `TermsAndConditionsDAO`.
  - Example: `AssetDAOImpl` (`@Repository("assetSharedDAO")`) — hand-written Oracle SQL against `AMS_ASSETS`/`AMS_ORDERS`/`AMS_ASSET_CONFIGS` with private static `RowMapper<T>` classes (`AssetDetailMapper`, `AssetMigratableMapper`, `DecommissionMapper`, ...). Methods like `getOrderForAsset(long,long)`, `getAssetStatus(long,long)`, `addAssetReturn(long,String,String)`, `getMigratableAssetsForCustomer(Customer)`.
- `dao.procs` — Spring `StoredProcedure` subclasses: `AddEntityEmailProcedure`, `CancelNCRDateProcedureSimple/Complex`, `ReserveTimeslotProcedure`.
- `service` / `service.impl` (`@Service("name")`, `@Transactional`) — `AdministrationService`, `BaseScheduleService`, `CalendarService`, `ConfigService`, `CustomerSearchService`, `CustomerService`, `AssetAttentionService`, `AssetConfigService`, `AssetSearchService`, `AssetService`/`AssetServiceImpl` (wires 7+ DAOs via field `@Autowired`), `EmailService`, `InstallationCalendarService`, `ModifyConfigurationService`, `NetworkChangeRequestScheduleService`, `NetworkChangeRequestService`, `OrderService`, `PreLoadService`, `RequestService`, `TermsAndConditionsServiceImpl`, `ScheduleServiceTechlineImpl`, `ScheduleInstallationServiceImpl`, `SaveForLaterServiceImpl`, `RestServiceImpl`, `RestLoggingServiceImpl`.
- `model.address` — REST DTOs for an external address-validation call: `AddressValidationRequest`/`Response`, `ValidatableAddress`, `ValidatedAddress`, `ValidatedQualityType`, `Error`, `ErrorDetail`.
- `logging` — `AlertLoggingInterceptor` (Spring AOP interceptor used to wrap Service/DAO beans for infra alert logging), `LoggingConstants`, `LoggingUtils`.
- `helper` — `AssetHelper`, `OrderHelper`, `ParameterRepository`, `AbstractBaseTest` (test base).
- `utils` — `CommonConstants`, `ConversionUtils`, `RestLogger`.

**Tests**: JUnit4 + Mockito (`mockito-all`), integration-style DAO tests extending `AbstractBaseTest`, Spring context loaded from `test-context-h2.xml` (declares an **H2 embedded in-memory DataSource** via `<jdbc:embedded-database>`, running ~90 `<jdbc:script>` DDL/DML files creating ~60 `AMS_*`/`UTIL_*` tables, sequences, and views like `AMS_NCR_SCHEDULES_EXT_V`) + `test-context-scan.xml` (`<context:component-scan base-package="org.example.am"/>` plus an explicit `RestLogger` bean). No DBUnit — pure SQL-script seeding.

---

## 5. `ams-internal` Module — Main Application

Base package: `org.example.am.internal.*` (depends on the shared `org.example.am.shared.*` library above).

### AssetManagementInternalCommon (`org.example.am.internal.domain`, `.security`, `.utils`)
Small module (~14 files) holding internal-specific domain/security types (e.g. `SecurityRoleType` — ~50 fine-grained role constants such as `INT_SEARCH_ASSETS`, `INT_VIEW_ACH`, `INT_CANCEL_ORDER`, `INT_ADMIN_UTILITIES`, `INT_VIEW_NCR_HISTORY`, looked up via a `LinkedHashMap<String,SecurityRoleType>`), plus a `domain.comparator` sub-package.

### AssetManagementInternalServices (`org.example.am.internal.service`)
- `service.dao` / `service.dao.impl` — `CalendarServiceDAO`, `CustomerDAO`, `AssetDAO`, `AmsServicesDAO`, `AmsUserDetailsDAO`, `SaveForLaterDAO`, `StoredProcedureDAO`, each backed by hand-written Oracle SQL (`SYSTIMESTAMP`, `ROWNUM <= 1`, old-style outer-join syntax `AD.ASSET_ID (+)`).
- `service.dao.procs` — `ReserveTimeslotProcedure`, `ReserveNCRDateProcedureSimple/Complex`, `ReserveDecommissionDateProcedure`, `CancelTimeslotProcedure`, `CancelNCRDateProcedureSimple/Complex`, `CancelDecommissionDateProcedure`, `AddEntityEmailProcedure` — each a Spring `StoredProcedure` subclass with declared `SqlParameter`s; instantiated directly (`new X(dataSource)`, not Spring beans) from `StoredProcedureDAOImpl.init(DataSource)`.
- `service` / `service.impl` — `CustomerService`, `AssetService`, `CalendarService` (business rules: techline/install-date computation honoring min lead times + business-day math + holiday exclusion via DAO; NCR reserve/cancel routes to Simple vs Complex stored proc based on `NetworkChangeRequestType.SITE_TYPE_CHANGE`; decommission scheduling with a 42-day max scheduling window), `AmsServicesService`, `SaveForLaterService`, `AmsUserDetailsService`/`Impl` (implements the Spring Security `AuthenticationUserDetailsService`-style `loadUserDetails(Authentication)` contract, backed by `AmsUserDetailsDAOImpl` which resolves DB-driven LDAP-group → role mappings).
All transactional methods use `@Transactional` with `DataSourceTransactionManager` (JDBC-based, no JPA).

### AssetManagementInternalWeb (WAR — Struts2 + Spring MVC hybrid, ~145+ Java files)

**Packages**: `web.action`, `web.action.util`, `web.config`, `web.controller`, `web.filter`, `web.interceptors`, `web.listener`, `web.model`, `web.security`, `web.security.csrf`.

**`web.config` classes** (all `@Configuration`):
- `RootConfig` — `@ComponentScan(basePackages="org.example.am")` excluding `*Controller` and other `@Configuration` classes; `@Import({DataSourceConfig, GlobalSecurityConfig, WebSecurityConfig, RestConfig})`; declares a `BeanNameAutoProxyCreator` wrapping beans matching `*Service`/`*DAO`/`*Impl`/`*Initializer` with `AlertLoggingInterceptor`; declares a `ReloadableResourceBundleMessageSource` reading `appVersion` + `messages` properties files.
- `ServletConfig` — `@EnableWebMvc`, `@ComponentScan("org.example.am.internal.web.controller")`, `@Import(WebSecurityConfig)`, `@EnableGlobalMethodSecurity(prePostEnabled=true, jsr250Enabled=true, securedEnabled=true)`; static-resource handler `/resources/**`; registers `SpecialCharacterInterceptor` as an MVC `HandlerInterceptor`; `InternalResourceViewResolver` (JstlView, prefix `/WEB-INF/`, suffix `.jsp`); forces extension-based content negotiation (html/json); **disables the Spring 5.3 `PathPatternParser`** (sets pattern parser to null) to preserve legacy suffix-based path matching — reproduce this exact compatibility shim if targeting Spring 5.3.x, or otherwise ensure suffix-pattern URL matching still works.
- `WebSecurityConfig extends WebSecurityConfigurerAdapter` — permits without auth: `/Unauthorized.action*`, `/CustomError.action*`, `/health`, `/health.action`; everything else requires `ROLE_USER`; `httpBasic` entry point = `Http403ForbiddenEntryPoint` (no login redirect); `maximumSessions(1)` with `expiredUrl=/ams/invalidSessionError`; custom `CSRFTokenRequestMatcher`; security headers (frame-options SAMEORIGIN, HSTS, X-XSS-Protection, X-Content-Type-Options nosniff, cache-control no-store, CSP `script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'`); registers a pre-authenticated header filter that is **profile-gated**: `WebSealRequestHeaderAuthenticationFilter` (reads `iv-user`/`iv-groups` headers) for `production`/`qa` profiles, `DevWebSealRequestHeaderAuthenticationFilter` (local stub, e.g. hardcoded/dev user) for `local`/`dev`/`fit`; a `RemoveRolesPrefixPostProcessor` strips a role-name prefix from resolved authorities before role checks.
- `GlobalSecurityConfig extends GlobalMethodSecurityConfiguration` — registers `WebSealPreAuthenticatedAuthenticationProvider` wired to `AmsUserDetailsService` as the pre-auth `AuthenticationUserDetailsService`.
- `DataSourceConfig` — JNDI lookup of `jdbc/amsInternalDS` via `JndiDataSourceLookup` (`resourceRef=true`), `DataSourceTransactionManager`, `@EnableTransactionManagement`.
- `RestConfig` — wires `RestTemplate`/`ObjectMapper`/`RestLogger` via `RestSharedTemplateFactory(ConfigService, RestLogger)` for outbound REST calls (e.g. address validation).

**Security domain model** (`web.security`): `AmsUser implements UserDetails` (username, blank password, authorities, emailAddress, ldapGroups, customer); `AmsRole implements GrantedAuthority`; `WebSealPrincipal` (username, emailAddress, aba, ldapGroups, firstName, lastName — populated from WebSEAL headers, fed into `PreAuthenticatedAuthenticationToken`).

**Struts2 Actions** (`web.action`, `@Component("ActionName") @Scope("prototype")`, extend `BaseAction extends ActionSupport implements ServletRequestAware, ServletResponseAware, ModelDriven<Object>`):

`BaseAction` centralizes: role checks (`request.isUserInRole(role.getCode())`), session access, `AmsUser`/`Customer` lookup from `SecurityContextHolder`, ajax-token session attribute check, a `currentTimeOverride` session attribute (QA time-travel feature), `ResourceBundle` message lookup, field/action-error helpers, and an environment-driven "pointing to non-prod env" warning-banner check.

Recreate this full action inventory (36 classes) grouped by feature area, each mapped from a `struts-<area>.xml` file included by the root `struts.xml`:
- **Asset management** (`struts-assetManagement.xml`, ns `/assetManagement`): `SearchAction` (`initSearch`, `search`, `getCustomers`, `validateUserSearch` — role-gated, delegates to shared `CustomerSearchService`/`AssetSearchService`, builds grid DTOs with inline HTML anchors for legacy Dojo grid actions), `DashboardAction` (`initDashboard`, `getDashboardLayout`).
- **Ajax** (`struts-ajax.xml`): `AjaxAssetAttentionAction`, `AjaxEnableEmergencyReplacementAction`, `AjaxEventAction`, `AjaxInstallationAction`, `AjaxSavedNCRAction`, `AjaxSavedOrderAction`, `AjaxTechlineAction`.
- **Customer** (`struts-customer.xml`, ns `/customer`): `CustomerAdminAction` (`initCustomerAdmin`, `updateCanSubmitOrders` → JSON result, `showEnableOrdering`), `AssetInstallationsAction`.
- **Order** (`struts-order.xml`, ns `/order` — the largest module): `OrderBaseAction` (superclass with address-length validation ≤26/≤20 chars), `OrderNewAction.initOrder`, `OrderSelectAssetAction` (`SelectAsset`/`SelectEmergencyReplacementAsset`), `OrderBeginAction`, `OrderSaveForLaterAction` (`SaveForLater`/`ContinueOrder`), `OrderReviewAction extends OrderBaseAction` (`reviewOrder`/`reviewOrderPrevious`/`reviewOrderInput`, integrates `AddressValidationInterceptor` with result codes `av.success`/`av.suggestion`/`av.error`), `OrderSubmitAction`, `OrderConfirmationAction`, `OrderCancelAction`, `OrderAction` (huge JSON action `GetLegacyAssetConfig` dumping ~90 asset/network-config fields; also handles modify-configuration and move-asset sub-flows via many named methods).
- **Calendar** (`struts-calendar.xml`): `CalendarAction` (`techLineTimeSlots`, `installationTimeSlots`, `installationTimeSlotsModifiedForDashboardTechline`, `serviceTimeSlots`).
- **User** (`struts-user.xml`): `UserAction` — `changeUser`/`submitChangeUser`, a **dev/test-only** LDAP-group/clock impersonation feature gated by a `PropertyType` flag; rebuilds a `PreAuthenticatedAuthenticationToken` with swapped authorities and can override session "current time". Flag clearly as non-production and gate behind config, or omit if not needed.
- **Cancel** (`struts-cancel.xml`): `CancelAction` — `cancelOrder`/`submitCancelOrder`/`cancelModifyConfiguration`/`submitCancelModifyConfiguration`, penalty-window calc via `PropertyType.MIN_HOURS_BEFORE_INSTALLATION_TO_CANCEL_ORDER_WITHOUT_PENALTY`.
- **Services** (`struts-services.xml`): `AmsServicesAction`.
- **Assets** (`struts-assets.xml`): `AssetAction`, `DecommissionAction`, `CompareConfigAction`, `ResolveConfigurationMismatchAction`, `UpdateInstallAddressAction`, plus `util/AssetStatusHelper`.
- **Terms and conditions** (`struts-termsAndConditions.xml`): `TermsAndConditionsAction`.
- **Network change request** (`struts-networkChangeRequest.xml`): `NetworkChangeRequestAction`, `NetworkChangeRequestDetailsAction`, `NetworkChangeRequestHistoryAction`, `RescheduleNcrAction`.
- **Admin** (`struts-admin.xml`, ns `/admin`): `AdminUtilitiesAction.initAdminUtilities` → `adminUtilities.jsp`.
- **Health** (`struts-health.xml`, ns `/`): `HealthAction` — plain-text "OK", `NONE` result, `struts.action.extension=,action` allows both `/health` and `/health.action`; explicitly `permitAll()` in security config.
- **Errors**: `ErrorAction`, `JsonErrorAction` (returns a `JsonErrorModel{invalidSession=true, message=INVALID_SESSION}` for JSON clients), `SavedFormAction`, `StateAction`, `TechLineAction`, `InstallationAction`.

**Struts config wiring conventions to reproduce**:
- Root `struts.xml`: `struts.enable.DynamicMethodInvocation=false`, `struts.devMode=false`, excludes `/ams/.*?` from Struts handling, includes all `struts-*.xml` sub-files, defines a base `AssetManagementInternalWeb` package extending `json-default` with shared interceptor stacks (`basicStack`, `defaultStack`, `modelDrivenStack`, `assetManagementStack`, `assetManagementJsonStack`, `AdminUtilJsonStack`) that all log exceptions to a dedicated application logger category, plus global results `custom_error`/`invalid.token`/`invalid.json.token`/`unauthorized`/`error` and a global exception mapping to `custom_error`.
- Custom interceptors (`web.interceptors`, all Struts2 `AbstractInterceptor`): `ValidateSpecialCharacterInterceptor` (whitelist-regex validates all action params, else action error + `"input"` result), `AjaxTokenInterceptor` (compares request param vs session `ajaxToken`, else `"invalid.token"`), `AjaxJsonTokenInterceptor extends AjaxTokenInterceptor` (remaps to `"invalid.json.token"`), `SecurityHeadersInterceptor` (sets the same security headers as Spring Security's filter, duplicated for the Struts path), `AddressValidationInterceptor` (`ModelDriven<OrderModel>`, only fires for domestic `US` shipping addresses on eligible asset types, calls shared `RestService.postAddressValidation(...)`, sets `av.success`/`av.suggestion`/`av.error`).
- `AjaxTokenListener implements HttpSessionListener` — generates a GUID into session attribute `ajaxToken` on session creation (CSRF-like token for Struts AJAX POSTs, independent of Spring Security's own CSRF matcher).
- Servlet filters (`web.filter`): `LoggingFilter` (sets MDC-style `LoggingUtils.setUserId`/`setActivityType` per request, cleared in `finally`), `StaticContentCachingHeaderFilter` (`Cache-Control: max-age=600, private` on `/js/*`, `/css/*`, `/images/*`, `/resources/*`).
- Spring MVC (`web.controller`): only ONE real controller — `ErrorController` (`@Controller`) mapping `GET /invalidSessionError` → view `"invalidSession"`, `GET /error` → view `"customError"`, `@ExceptionHandler(Exception.class)` → `"customError"`. `SpecialCharacterInterceptor` (Spring MVC `HandlerInterceptor` counterpart to the Struts version) validates every request param against the whitelist regex `[0-9A-Za-z\s'.,\-_:*@/#$()=%+&?^\`|~]*`, throwing a `SpecialCharacterException` on violation.

**`web.xml`** — reproduce exactly this wiring:
```
Listeners: ContextLoaderListener (contextClass=AnnotationConfigWebApplicationContext, contextConfigLocation=...web.config.RootConfig),
           AjaxTokenListener, ApplicationVersionListener (custom)
Filters (all mapped /* unless noted):
  springSecurityFilterChain (DelegatingFilterProxy)
  loggingFilter (custom LoggingFilter)
  staticContentCacheFilter (custom, mapped only to /js/*,/css/*,/images/*,/resources/*)
  etagFilter (Spring ShallowEtagHeaderFilter, same static paths)
  struts2 (StrutsPrepareAndExecuteFilter)
Servlet: DispatcherServlet "ams" (contextClass=AnnotationConfigWebApplicationContext,
         contextConfigLocation=...web.config.ServletConfig), mapped to /ams/*
Welcome file: index.jsp
Error pages: 404/405 -> /resources/pages/errorRedirect.jsp, 500 -> /WEB-INF/global/customError.jsp
```

**View layer**: JSPs under `WEB-INF/{admin,calendar,cancel,common,contacts,customer,assetManagement,assets,fedLineServices,global,order,user}/*.jsp` (48 JSPs total) rendered via Struts2 result mappings and the Spring `InternalResourceViewResolver`. Frontend JS toolkit: **Dojo Toolkit 1.17.3** (vendored under `js/dojo-release-1.17.3/`, not npm-managed) plus custom `js/common.js`, `css/main.js`. No modern JS build tooling (no package.json/webpack/npm) — static vendored assets only.

**Logging config** (`log4j2.xml`): Console + rolling-file appenders as described in section 3; per-logger levels: application base package `=debug`, `org.springframework=warn`, `com.opensymphony.xwork2=warn`, `org.apache=warn`, `freemarker.cache=warn`.

### AssetManagementInternalEar
Packaging-only module (`ear`), no Java. `maven-ear-plugin` config: `defaultLibBundleDir=lib`, `addClasspath=true`, single `<webModule>` referencing the Web WAR with the configured context-root.

---

## 6. Build a Verification Checklist

When the replica is complete, verify:
1. `mvn clean install` succeeds across all three reactors in dependency order (`ams-parent-bom` → `ams-common` → `ams-internal`), each installed to local/remote Maven repo before the next builds.
2. `AssetManagementInternalWeb.war` builds and deploys into a WebSphere Liberty container matching the `server.xml` feature set; `/health` and `/health.action` return `200 OK` with plain-text body, unauthenticated.
3. Any other path returns `401/403` unless a valid pre-authenticated `iv-user`/`iv-groups` header (or the local dev stub filter) is present — confirms `WebSecurityConfig` wiring.
4. DAO/service integration tests (`mvn test` in `AssetManagementSharedServices` and `AssetManagementInternalServices`) run against the H2 in-memory schema seeded from `test-context-h2.xml`-equivalent scripts, with no Hibernate/JPA dependency present anywhere on the classpath.
5. Struts action URLs (e.g. `/order/InitOrder.action`, `/assetManagement/Search.action`, `/customer/CustomerAdmin.action`) resolve to their mapped JSPs; confirm the `/ams/*` Spring MVC path only serves the two error views.
