# Architecture and Patterns Guide

> **Version**: 1.0.0
> **Date**: 2026-02-02
> **Author**: la organización
> **Purpose**: Comprehensive guide for architecture selection in .NET projects

---

## Index

1. [Introduction](#1-introduction)
2. [Architecture Profiles](#2-architecture-profiles)
3. [BASIC Profile - Services + Repository](#3-basic-profile)
4. [STANDARD Profile - Clean Architecture + Mediator](#4-standard-profile)
5. [ADVANCED Profile - CQRS + Mediator](#5-advanced-profile)
6. [Pattern Comparison](#6-pattern-comparison)
7. [Mediator vs MediatR - Technical Decision](#7-mediator-vs-mediatr)
8. [Selection Guide](#8-selection-guide)
9. [Implementation by Profile](#9-implementation-by-profile)
10. [Migration Between Profiles](#10-migration-between-profiles)
11. [References](#11-references)

---

## 1. Introduction

### 1.1 Purpose of this document

This document provides a comprehensive guide for selecting the appropriate architecture in .NET projects. It defines three predefined architecture profiles that cover 95% of use cases.

### 1.2 ecosystem design principles

| Principle | Description |
|-----------|-------------|
| **Simplicity** | Don't overdesign. Choose minimum necessary complexity |
| **Maintainability** | Code that others can understand and modify |
| **Testability** | Facilitate unit and integration testing |
| **Scalability** | Allow growth without rewriting |

### 1.3 Project reality

```
Typical project distribution:

70% ─────────────────────────────── CRUD + basic logic
     Managers, internal portals, ABMs

20% ───────── Moderate logic
     Integrations, workflows, complex validations

10% ── Complex domains
     Critical systems, high scale, event sourcing
```

---

## 2. Architecture Profiles

### 2.1 Profile summary

| Profile | Pattern | Complexity | Files/Entity | Ideal for |
|---------|---------|------------|--------------|-----------|
| **BASIC** | Services + Repository | ⭐ | 4-6 | CRUD, MVPs, prototypes |
| **STANDARD** | Clean + Mediator | ⭐⭐ | 8-12 | REST APIs, business apps |
| **ADVANCED** | CQRS + Mediator | ⭐⭐⭐ | 15-20 | Complex domains |

### 2.2 Decision diagram

```
                    What type of project is it?
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
         CRUD >80%       CRUD 50-80%      CRUD <50%
         Simple logic   Moderate logic  Complex logic
              │               │               │
              ▼               ▼               ▼
         ┌────────┐     ┌──────────┐    ┌──────────┐
         │ BASIC  │     │ STANDARD │    │ ADVANCED │
         └────────┘     └──────────┘    └──────────┘
```

---

## 3. BASIC Profile

### 3.1 Description

The BASIC profile implements a 2-3 layer architecture with direct service injection. It does not use the Mediator pattern.

### 3.2 Architecture diagram

```
┌──────────────────────────────────────────────────────────────┐
│                      BASIC PROFILE                           │
│                  Services + Repository                       │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌─────────────┐                                           │
│   │ Controller  │                                           │
│   │             │                                           │
│   └──────┬──────┘                                           │
│          │ Direct injection                                 │
│          ▼                                                  │
│   ┌─────────────┐                                           │
│   │   Service   │  ◄── Business logic                      │
│   │             │      Validations                         │
│   └──────┬──────┘      DTO mapping                         │
│          │                                                  │
│          ▼                                                  │
│   ┌─────────────┐                                           │
│   │ Repository  │  ◄── Data access                         │
│   │             │      EF Core DbContext                    │
│   └──────┬──────┘                                           │
│          │                                                  │
│          ▼                                                  │
│   ┌─────────────┐                                           │
│   │  Database   │                                           │
│   └─────────────┘                                           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 3.3 Project structure

```
MyCompany.MyApp/
├── MyCompany.MyApp.sln
│
├── src/
│   ├── MyCompany.MyApp.Api/           # Controllers + Startup
│   │   ├── Controllers/
│   │   │   └── ScholarshipsController.cs
│   │   ├── appsettings.json
│   │   └── Program.cs
│   │
│   └── MyCompany.MyApp.Core/          # Everything else
│       ├── Entities/
│       │   └── Scholarship.cs
│       ├── DTOs/
│       │   ├── ScholarshipDto.cs
│       │   └── CreateScholarshipRequest.cs
│       ├── Services/
│       │   ├── IScholarshipService.cs
│       │   └── ScholarshipService.cs
│       ├── Repositories/
│       │   ├── IScholarshipRepository.cs
│       │   └── ScholarshipRepository.cs
│       ├── Data/
│       │   └── ApplicationDbContext.cs
│       └── DependencyInjection.cs
│
└── tests/
    └── MyCompany.MyApp.Tests/
        └── Services/
            └── ScholarshipServiceTests.cs
```

### 3.4 Code example

```csharp
// ═══════════════════════════════════════════════════════════════
// CONTROLLER - Direct service injection
// ═══════════════════════════════════════════════════════════════

[ApiController]
[Route("api/[controller]")]
public class ScholarshipsController : ControllerBase
{
    private readonly IScholarshipService _scholarshipService;

    public ScholarshipsController(IScholarshipService scholarshipService)
    {
        _scholarshipService = scholarshipService;
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<ScholarshipDto>> Get(int id, CancellationToken ct)
    {
        var scholarship = await _scholarshipService.GetByIdAsync(id, ct);
        if (scholarship is null) return NotFound();
        return Ok(scholarship);
    }

    [HttpPost]
    public async Task<ActionResult<ScholarshipDto>> Create(
        CreateScholarshipRequest request, CancellationToken ct)
    {
        var scholarship = await _scholarshipService.CreateAsync(request, ct);
        return CreatedAtAction(nameof(Get), new { id = scholarship.Id }, scholarship);
    }
}

// ═══════════════════════════════════════════════════════════════
// SERVICE - Contains business logic
// ═══════════════════════════════════════════════════════════════

public interface IScholarshipService
{
    Task<ScholarshipDto?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<ScholarshipDto>> GetAllAsync(CancellationToken ct = default);
    Task<ScholarshipDto> CreateAsync(CreateScholarshipRequest request, CancellationToken ct = default);
    Task UpdateAsync(int id, UpdateScholarshipRequest request, CancellationToken ct = default);
    Task DeleteAsync(int id, CancellationToken ct = default);
}

public class ScholarshipService : IScholarshipService
{
    private readonly IScholarshipRepository _repository;
    private readonly ILogger<ScholarshipService> _logger;

    public ScholarshipService(IScholarshipRepository repository, ILogger<ScholarshipService> logger)
    {
        _repository = repository;
        _logger = logger;
    }

    public async Task<ScholarshipDto?> GetByIdAsync(int id, CancellationToken ct = default)
    {
        var scholarship = await _repository.GetByIdAsync(id, ct);
        return scholarship?.ToDto();
    }

    public async Task<ScholarshipDto> CreateAsync(
        CreateScholarshipRequest request, CancellationToken ct = default)
    {
        // Business validation
        if (request.Amount <= 0)
            throw new ValidationException("Amount must be positive");

        var scholarship = new Scholarship
        {
            Name = request.Name,
            Amount = request.Amount,
            CreatedAt = DateTime.UtcNow
        };

        await _repository.AddAsync(scholarship, ct);

        _logger.LogInformation("Scholarship {ScholarshipId} created", scholarship.Id);

        return scholarship.ToDto();
    }
}

// ═══════════════════════════════════════════════════════════════
// REPOSITORY - Data access
// ═══════════════════════════════════════════════════════════════

public interface IScholarshipRepository
{
    Task<Scholarship?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<Scholarship>> GetAllAsync(CancellationToken ct = default);
    Task AddAsync(Scholarship scholarship, CancellationToken ct = default);
    Task UpdateAsync(Scholarship scholarship, CancellationToken ct = default);
    Task DeleteAsync(Scholarship scholarship, CancellationToken ct = default);
}

public class ScholarshipRepository : IScholarshipRepository
{
    private readonly ApplicationDbContext _context;

    public ScholarshipRepository(ApplicationDbContext context)
    {
        _context = context;
    }

    public async Task<Scholarship?> GetByIdAsync(int id, CancellationToken ct = default)
    {
        return await _context.Scholarships.FindAsync(new object[] { id }, ct);
    }

    public async Task AddAsync(Scholarship scholarship, CancellationToken ct = default)
    {
        await _context.Scholarships.AddAsync(scholarship, ct);
        await _context.SaveChangesAsync(ct);
    }
}
```

### 3.5 When to use BASIC

**Use when:**
- CRUD operations represent >80% of the system
- Short duration project (<6 months)
- Small team (1-2 people) or junior
- Prototype or MVP that may evolve
- No high scalability requirements

**DO NOT use when:**
- Complex business logic with many rules
- You need centralized cross-cutting concerns (logging, validation, caching)
- The project will grow significantly
- Extensive testing is required

### 3.6 Advantages and disadvantages

| Advantages | Disadvantages |
|------------|---------------|
| Maximum simplicity | Controllers coupled to services |
| Minimal learning curve | No pipeline behaviors |
| F12 works directly | Manual cross-cutting concerns |
| Fewer files to maintain | Difficult to evolve to CQRS |
| Ideal for junior teams | More coupled testing |

---

## 4. STANDARD Profile

### 4.1 Description

The STANDARD profile implements Clean Architecture with the Mediator pattern to decouple controllers from handlers. Includes pipeline behaviors for logging, validation and other cross-cutting concerns.

### 4.2 Architecture diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     STANDARD PROFILE                         │
│              Clean Architecture + Mediator                   │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌─────────────┐                                           │
│   │ Controller  │                                           │
│   └──────┬──────┘                                           │
│          │                                                  │
│          ▼                                                  │
│   ┌─────────────┐     ┌─────────────────────────────────┐  │
│   │  Mediator   │────►│         APPLICATION             │  │
│   └─────────────┘     │                                 │  │
│                       │  ┌──────────┐   ┌───────────┐   │  │
│                       │  │ Request  │──►│  Handler  │   │  │
│                       │  └──────────┘   └─────┬─────┘   │  │
│                       │                       │         │  │
│                       │  Pipeline Behaviors:  │         │  │
│                       │  ├─ Validation        │         │  │
│                       │  ├─ Logging           │         │  │
│                       │  └─ Performance       │         │  │
│                       └───────────────────────┼─────────┘  │
│                                               │             │
│                                      ┌────────▼────────┐   │
│                                      │     DOMAIN      │   │
│                                      │   (Entities)    │   │
│                                      └────────┬────────┘   │
│                                               │             │
│                                      ┌────────▼────────┐   │
│                                      │ INFRASTRUCTURE  │   │
│                                      │  (Repository)   │   │
│                                      └─────────────────┘   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 4.3 Project structure

```
MyCompany.MyApp/
├── MyCompany.MyApp.sln
│
├── src/
│   ├── MyCompany.MyApp.Api/
│   │   ├── Controllers/
│   │   │   └── ScholarshipsController.cs
│   │   └── Program.cs
│   │
│   ├── MyCompany.MyApp.Application/
│   │   ├── Common/
│   │   │   ├── Behaviours/
│   │   │   │   ├── ValidationBehaviour.cs
│   │   │   │   └── LoggingBehaviour.cs
│   │   │   └── Interfaces/
│   │   │       └── IUnitOfWork.cs
│   │   ├── Scholarships/
│   │   │   ├── Commands/
│   │   │   │   ├── CreateScholarship/
│   │   │   │   │   ├── CreateScholarshipCommand.cs
│   │   │   │   │   ├── CreateScholarshipCommandHandler.cs
│   │   │   │   │   └── CreateScholarshipCommandValidator.cs
│   │   │   │   └── UpdateScholarship/
│   │   │   │       └── ...
│   │   │   ├── Queries/
│   │   │   │   ├── GetScholarshipById/
│   │   │   │   │   ├── GetScholarshipByIdQuery.cs
│   │   │   │   │   ├── GetScholarshipByIdQueryHandler.cs
│   │   │   │   │   └── ScholarshipDto.cs
│   │   │   │   └── GetAllScholarships/
│   │   │   │       └── ...
│   │   │   └── EventHandlers/
│   │   │       └── ScholarshipCreatedEventHandler.cs
│   │   └── DependencyInjection.cs
│   │
│   ├── MyCompany.MyApp.Domain/
│   │   ├── Entities/
│   │   │   └── Scholarship.cs
│   │   ├── Events/
│   │   │   └── ScholarshipCreatedEvent.cs
│   │   └── Interfaces/
│   │       └── IScholarshipRepository.cs
│   │
│   └── MyCompany.MyApp.Infrastructure/
│       ├── Data/
│       │   └── ApplicationDbContext.cs
│       ├── Repositories/
│       │   └── ScholarshipRepository.cs
│       └── DependencyInjection.cs
│
└── tests/
    ├── MyCompany.MyApp.Application.Tests/
    └── MyCompany.MyApp.Integration.Tests/
```

### 4.4 Code example

```csharp
// ═══════════════════════════════════════════════════════════════
// CONTROLLER - Uses Mediator
// ═══════════════════════════════════════════════════════════════

[ApiController]
[Route("api/[controller]")]
public class ScholarshipsController : ControllerBase
{
    private readonly IMediator _mediator;

    public ScholarshipsController(IMediator mediator)
    {
        _mediator = mediator;
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<ScholarshipDto>> Get(int id, CancellationToken ct)
    {
        var result = await _mediator.Send(new GetScholarshipByIdQuery(id), ct);
        if (result is null) return NotFound();
        return Ok(result);
    }

    [HttpPost]
    public async Task<ActionResult<int>> Create(
        CreateScholarshipCommand command, CancellationToken ct)
    {
        var id = await _mediator.Send(command, ct);
        return CreatedAtAction(nameof(Get), new { id }, id);
    }
}

// ═══════════════════════════════════════════════════════════════
// QUERY - Read
// ═══════════════════════════════════════════════════════════════

// Request
public record GetScholarshipByIdQuery(int Id) : IRequest<ScholarshipDto?>;

// Handler
public class GetScholarshipByIdQueryHandler : IRequestHandler<GetScholarshipByIdQuery, ScholarshipDto?>
{
    private readonly IScholarshipRepository _repository;

    public GetScholarshipByIdQueryHandler(IScholarshipRepository repository)
    {
        _repository = repository;
    }

    public async ValueTask<ScholarshipDto?> Handle(
        GetScholarshipByIdQuery request, CancellationToken ct)
    {
        var scholarship = await _repository.GetByIdAsync(request.Id, ct);
        return scholarship?.ToDto();
    }
}

// DTO
public record ScholarshipDto
{
    public int Id { get; init; }
    public string Name { get; init; } = string.Empty;
    public decimal Amount { get; init; }
    public DateTime CreatedAt { get; init; }
}

// ═══════════════════════════════════════════════════════════════
// COMMAND - Write
// ═══════════════════════════════════════════════════════════════

// Command
public record CreateScholarshipCommand : IRequest<int>
{
    public required string Name { get; init; }
    public decimal Amount { get; init; }
}

// Handler
public class CreateScholarshipCommandHandler : IRequestHandler<CreateScholarshipCommand, int>
{
    private readonly IScholarshipRepository _repository;
    private readonly IUnitOfWork _unitOfWork;

    public CreateScholarshipCommandHandler(
        IScholarshipRepository repository, IUnitOfWork unitOfWork)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
    }

    public async ValueTask<int> Handle(
        CreateScholarshipCommand request, CancellationToken ct)
    {
        var scholarship = new Scholarship
        {
            Name = request.Name,
            Amount = request.Amount,
            CreatedAt = DateTime.UtcNow
        };

        await _repository.AddAsync(scholarship, ct);
        await _unitOfWork.SaveChangesAsync(ct);

        return scholarship.Id;
    }
}

// Validator (FluentValidation)
public class CreateScholarshipCommandValidator : AbstractValidator<CreateScholarshipCommand>
{
    public CreateScholarshipCommandValidator()
    {
        RuleFor(x => x.Name)
            .NotEmpty().WithMessage("Name is required")
            .MaximumLength(200).WithMessage("Maximum 200 characters");

        RuleFor(x => x.Amount)
            .GreaterThan(0).WithMessage("Amount must be positive");
    }
}

// ═══════════════════════════════════════════════════════════════
// PIPELINE BEHAVIOR - Automatic validation
// ═══════════════════════════════════════════════════════════════

public class ValidationBehaviour<TRequest, TResponse>
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationBehaviour(IEnumerable<IValidator<TRequest>> validators)
    {
        _validators = validators;
    }

    public async ValueTask<TResponse> Handle(
        TRequest request,
        CancellationToken ct,
        MessageHandlerDelegate<TRequest, TResponse> next)
    {
        if (!_validators.Any())
            return await next(request, ct);

        var context = new ValidationContext<TRequest>(request);
        var failures = _validators
            .Select(v => v.Validate(context))
            .SelectMany(r => r.Errors)
            .Where(f => f != null)
            .ToList();

        if (failures.Count > 0)
            throw new ValidationException(failures);

        return await next(request, ct);
    }
}
```

### 4.5 Mediator configuration (martinothamar/Mediator)

```csharp
// Program.cs
builder.Services.AddMediator(options =>
{
    options.ServiceLifetime = ServiceLifetime.Scoped;
});

// With behaviors
builder.Services.AddSingleton(typeof(IPipelineBehavior<,>), typeof(ValidationBehaviour<,>));
builder.Services.AddSingleton(typeof(IPipelineBehavior<,>), typeof(LoggingBehaviour<,>));

// FluentValidation
builder.Services.AddValidatorsFromAssemblyContaining<CreateScholarshipCommandValidator>();
```

### 4.6 When to use STANDARD

**Use when:**
- Medium-sized project (6-18 months)
- Moderate business logic
- You need centralized cross-cutting concerns
- Testing is important
- Mixed team (junior + senior)
- Typical REST API with validations

**DO NOT use when:**
- Very simple CRUD (>80%)
- Very complex domain requiring real CQRS
- Critical time-to-market with no margin

### 4.7 Advantages and disadvantages

| Advantages | Disadvantages |
|------------|---------------|
| Clean decoupling | More files than BASIC |
| Pipeline behaviors | F12 doesn't reach handler directly |
| Facilitated testing | Medium learning curve |
| Easily testable | May seem overengineering |
| Scalable to CQRS | for simple CRUD |

---

## 5. ADVANCED Profile

### 5.1 Description

The ADVANCED profile implements full CQRS (Command Query Responsibility Segregation), separating read and write models. Allows optimizing each side independently.

### 5.2 Architecture diagram

```
┌──────────────────────────────────────────────────────────────┐
│                      ADVANCED PROFILE                        │
│                 CQRS + Mediator + Events                     │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   Controller                                                 │
│       │                                                      │
│       ▼                                                      │
│   ┌─────────┐                                               │
│   │ Mediator │                                               │
│   └────┬────┘                                               │
│        │                                                     │
│   ┌────┴────────────────────────────────────┐               │
│   │                                          │               │
│   ▼                                          ▼               │
│ ┌──────────────┐                    ┌──────────────┐        │
│ │   COMMANDS   │                    │   QUERIES    │        │
│ │   (Write)    │                    │   (Read)     │        │
│ │              │                    │              │        │
│ │ - Create     │                    │ - GetById    │        │
│ │ - Update     │                    │ - GetAll     │        │
│ │ - Delete     │                    │ - Search     │        │
│ └──────┬───────┘                    └──────┬───────┘        │
│        │                                   │                 │
│        ▼                                   ▼                 │
│ ┌──────────────┐                    ┌──────────────┐        │
│ │   Command    │                    │    Query     │        │
│ │   Handler    │                    │   Handler    │        │
│ └──────┬───────┘                    └──────┬───────┘        │
│        │                                   │                 │
│        ▼                                   ▼                 │
│ ┌──────────────┐                    ┌──────────────┐        │
│ │    DOMAIN    │                    │  READ MODEL  │        │
│ │ (Aggregates) │                    │   (DTOs)     │        │
│ │              │                    │              │        │
│ │ - Entities   │                    │ - Optimized  │        │
│ │ - ValueObj   │                    │ - Denormal.  │        │
│ │ - Rules      │                    │              │        │
│ └──────┬───────┘                    └──────┬───────┘        │
│        │                                   │                 │
│        │     Domain Events                 │                 │
│        │         │                         │                 │
│        ▼         ▼                         ▼                 │
│ ┌──────────────────────────────────────────────────┐        │
│ │              INFRASTRUCTURE                       │        │
│ │                                                   │        │
│ │  Write Repository    │    Read Repository         │        │
│ │  (EF Core)           │    (Dapper/EF)             │        │
│ └──────────────────────┴────────────────────────────┘        │
│        │                         │                           │
│        ▼                         ▼                           │
│   Write Store              Read Store                       │
│  (Normalized)           (Denormalized)                      │
│                                                              │
│        └──────── Sync/Events ────────┘                      │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 5.3 CQRS implementation levels

| Level | Description | Complexity | When to use |
|-------|-------------|------------|-------------|
| **1** | Same DB, different models | Low | Start here |
| **2** | Same DB, materialized views | Medium | Optimize reads |
| **3** | Separate DBs (eventual sync) | High | High scale |
| **4** | Event Sourcing | Very high | Complete audit |

### 5.4 Project structure

```
MyCompany.MyApp/
├── MyCompany.MyApp.sln
│
├── src/
│   ├── MyCompany.MyApp.Api/
│   │   └── Controllers/
│   │
│   ├── MyCompany.MyApp.Application/
│   │   ├── Commands/
│   │   │   └── Scholarships/
│   │   │       ├── CreateScholarship/
│   │   │       │   ├── CreateScholarshipCommand.cs
│   │   │       │   ├── CreateScholarshipCommandHandler.cs
│   │   │       │   └── CreateScholarshipCommandValidator.cs
│   │   │       ├── UpdateScholarship/
│   │   │       └── DeleteScholarship/
│   │   │
│   │   ├── Queries/
│   │   │   └── Scholarships/
│   │   │       ├── GetScholarshipById/
│   │   │       │   ├── GetScholarshipByIdQuery.cs
│   │   │       │   ├── GetScholarshipByIdQueryHandler.cs
│   │   │       │   └── ScholarshipReadModel.cs     ← Optimized model
│   │   │       └── SearchScholarships/
│   │   │           └── ...
│   │   │
│   │   └── Events/
│   │       └── Handlers/
│   │           └── ScholarshipCreatedEventHandler.cs
│   │
│   ├── MyCompany.MyApp.Domain/
│   │   ├── Aggregates/
│   │   │   └── Scholarship/
│   │   │       ├── Scholarship.cs              ← Aggregate Root
│   │   │       └── ScholarshipApplication.cs         ← Entity
│   │   ├── ValueObjects/
│   │   │   └── Period.cs
│   │   ├── Events/
│   │   │   └── ScholarshipCreatedEvent.cs
│   │   └── Interfaces/
│   │       ├── IScholarshipWriteRepository.cs
│   │       └── IScholarshipReadRepository.cs
│   │
│   └── MyCompany.MyApp.Infrastructure/
│       ├── Persistence/
│       │   ├── Write/
│       │   │   └── ScholarshipWriteRepository.cs
│       │   └── Read/
│       │       └── ScholarshipReadRepository.cs  ← Can use Dapper
│       └── EventHandlers/
│           └── UpdateReadModelHandler.cs
│
└── tests/
```

### 5.5 Code example

```csharp
// ═══════════════════════════════════════════════════════════════
// COMMAND - Write with Rich Domain
// ═══════════════════════════════════════════════════════════════

public record CreateScholarshipCommand : IRequest<Guid>
{
    public required string Name { get; init; }
    public decimal Amount { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime EndDate { get; init; }
}

public class CreateScholarshipCommandHandler : IRequestHandler<CreateScholarshipCommand, Guid>
{
    private readonly IScholarshipWriteRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IMediator _mediator;

    public async ValueTask<Guid> Handle(
        CreateScholarshipCommand request, CancellationToken ct)
    {
        // Create with domain logic
        var period = new Period(request.StartDate, request.EndDate);
        var scholarship = Scholarship.Create(request.Name, request.Amount, period);

        await _repository.AddAsync(scholarship, ct);
        await _unitOfWork.SaveChangesAsync(ct);

        // Publish domain events
        foreach (var domainEvent in scholarship.DomainEvents)
        {
            await _mediator.Publish(domainEvent, ct);
        }
        scholarship.ClearDomainEvents();

        return scholarship.Id;
    }
}

// ═══════════════════════════════════════════════════════════════
// QUERY - Read with optimized model
// ═══════════════════════════════════════════════════════════════

public record GetScholarshipByIdQuery(Guid Id) : IRequest<ScholarshipReadModel?>;

// Optimized read model (can be denormalized)
public record ScholarshipReadModel
{
    public Guid Id { get; init; }
    public string Name { get; init; } = string.Empty;
    public decimal Amount { get; init; }
    public string Status { get; init; } = string.Empty;
    public int TotalApplications { get; init; }  // Denormalized
    public DateTime CreatedAt { get; init; }
}

public class GetScholarshipByIdQueryHandler : IRequestHandler<GetScholarshipByIdQuery, ScholarshipReadModel?>
{
    private readonly IScholarshipReadRepository _readRepository;

    public async ValueTask<ScholarshipReadModel?> Handle(
        GetScholarshipByIdQuery request, CancellationToken ct)
    {
        // Optimized read (can use Dapper, views, etc.)
        return await _readRepository.GetByIdAsync(request.Id, ct);
    }
}

// ═══════════════════════════════════════════════════════════════
// DOMAIN - Aggregate with business logic
// ═══════════════════════════════════════════════════════════════

public class Scholarship : AggregateRoot
{
    public string Name { get; private set; } = null!;
    public decimal Amount { get; private set; }
    public Period Period { get; private set; } = null!;
    public ScholarshipStatus Status { get; private set; }

    private readonly List<ScholarshipApplication> _applications = [];
    public IReadOnlyCollection<ScholarshipApplication> Applications => _applications.AsReadOnly();

    private Scholarship() { }

    private Scholarship(string name, decimal amount, Period period)
    {
        Name = name;
        Amount = amount;
        Period = period;
        Status = ScholarshipStatus.Draft;
    }

    public static Scholarship Create(string name, decimal amount, Period period)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new DomainException("Name is required");

        if (amount <= 0)
            throw new DomainException("Amount must be positive");

        var scholarship = new Scholarship(name.Trim(), amount, period);
        scholarship.AddDomainEvent(new ScholarshipCreatedEvent(scholarship.Id, name));

        return scholarship;
    }

    public void Publish()
    {
        if (Status != ScholarshipStatus.Draft)
            throw new DomainException("Only draft grants can be published");

        if (!Period.IsFuture())
            throw new DomainException("Cannot publish a grant with past period");

        Status = ScholarshipStatus.Published;
        AddDomainEvent(new ScholarshipPublishedEvent(Id));
    }
}

// ═══════════════════════════════════════════════════════════════
// EVENT HANDLER - Synchronize read model
// ═══════════════════════════════════════════════════════════════

public class ScholarshipCreatedEventHandler : INotificationHandler<ScholarshipCreatedEvent>
{
    private readonly IScholarshipReadRepository _readRepository;

    public async ValueTask Handle(ScholarshipCreatedEvent notification, CancellationToken ct)
    {
        // Update denormalized read model
        await _readRepository.UpsertReadModelAsync(notification.ScholarshipId, ct);
    }
}
```

### 5.6 When to use ADVANCED

**Use when:**
- Very complex domain with many business rules
- High read/write disparity (>10:1)
- Need to scale reads independently
- Event Sourcing is required
- Complete change audit
- Senior team with DDD/CQRS experience

**DO NOT use when:**
- Simple or moderate CRUD
- Team without CQRS experience
- Critical time-to-market
- Small or medium project

### 5.7 Advantages and disadvantages

| Advantages | Disadvantages |
|------------|---------------|
| Independent R/W optimization | Significant complexity |
| Superior scalability | Eventual consistency |
| Natural auditing | Many more files |
| Specialized models | High learning curve |
| Domain-Driven Design | More difficult debugging |

---

## 6. Pattern Comparison

### 6.1 Services vs Mediator

```
┌─────────────────────────────────────────────────────────────────┐
│                    SERVICES (Direct injection)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Controller ──────────────► Service ──────────────► Repository │
│                                                                 │
│   Pros:                        Cons:                            │
│   ✅ Simple                    ❌ Controllers coupled           │
│   ✅ F12 works                 ❌ No pipeline behaviors         │
│   ✅ Fewer files               ❌ Manual cross-cutting          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    MEDIATOR (Handlers)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Controller ──► Mediator ──► Handler ──► Repository            │
│                      │                                          │
│                      └──► Pipeline Behaviors                    │
│                           ├── Validation                        │
│                           ├── Logging                           │
│                           └── Caching                           │
│                                                                 │
│   Pros:                        Cons:                            │
│   ✅ Decoupled                 ❌ More files                    │
│   ✅ Pipeline behaviors        ❌ Indirect F12                  │
│   ✅ Testable                  ❌ Learning curve                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Without CQRS vs With CQRS

```
┌─────────────────────────────────────────────────────────────────┐
│                    WITHOUT CQRS (Same model)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Read ──────┐                                                  │
│              ├──► Same Model ──► Same Repository ──► Same DB    │
│   Write ─────┘                                                  │
│                                                                 │
│   Pros:                        Cons:                            │
│   ✅ Simple                    ❌ Not optimizable separately    │
│   ✅ Strong consistency        ❌ Compromise model              │
│   ✅ One model                 ❌ Limited scale                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    WITH CQRS (Separate models)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Read ──► Query ──► Read Model ──► Read Repo ──► Read Store    │
│                                                                 │
│   Write ──► Command ──► Domain ──► Write Repo ──► Write Store   │
│                                         │                       │
│                                    Events/Sync                  │
│                                         │                       │
│                                         ▼                       │
│                                   Update Read Store             │
│                                                                 │
│   Pros:                        Cons:                            │
│   ✅ Optimizable separately    ❌ Eventual consistency          │
│   ✅ Independent scale         ❌ Complexity                    │
│   ✅ Specialized models        ❌ Synchronization               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 Code quantity by profile

For a "Scholarship" entity with complete CRUD:

| Profile | Files | Approx. lines | Classes |
|---------|-------|---------------|---------|
| BASIC | 6-8 | 200-300 | 4-5 |
| STANDARD | 12-15 | 400-600 | 10-12 |
| ADVANCED | 20-25 | 700-1000 | 18-22 |

---

## 7. Mediator vs MediatR

### 7.1 The problem with MediatR

As of version 12, **MediatR changed to commercial license**:

| Version | License | Cost |
|---------|---------|------|
| v11 and earlier | Apache 2.0 | Free |
| v12+ | Commercial | ~$500-2000/year for companies >$1M revenue |

### 7.2 Recommended alternatives

| Alternative | License | API compatible | Performance |
|-------------|---------|----------------|-------------|
| **Mediator (Othamar)** | MIT | 95% | Better (source gen) |
| MediatR v11 | Apache 2.0 | 100% | Good |
| Wolverine | MIT | 60% | Similar |
| Own implementation | - | Variable | Variable |

### 7.3 Ecosystem recommendation

```
OFFICIAL RECOMMENDATION:

For new projects → martinothamar/Mediator (MIT, free)
For existing projects → Evaluate migration or stay on v11

NuGet: Mediator.Abstractions + Mediator.SourceGenerator
GitHub: github.com/martinothamar/Mediator
```

### 7.4 MediatR to Mediator migration

```csharp
// ═══════════════════════════════════════════════════════════════
// BEFORE (MediatR)
// ═══════════════════════════════════════════════════════════════

using MediatR;

public record GetScholarshipQuery(int Id) : IRequest<ScholarshipDto?>;

public class GetScholarshipHandler : IRequestHandler<GetScholarshipQuery, ScholarshipDto?>
{
    public async Task<ScholarshipDto?> Handle(
        GetScholarshipQuery request, CancellationToken ct)
    {
        // ...
    }
}

// ═══════════════════════════════════════════════════════════════
// AFTER (Mediator)
// ═══════════════════════════════════════════════════════════════

using Mediator;  // ← Namespace change

public record GetScholarshipQuery(int Id) : IRequest<ScholarshipDto?>;

public class GetScholarshipHandler : IRequestHandler<GetScholarshipQuery, ScholarshipDto?>
{
    public async ValueTask<ScholarshipDto?> Handle(  // ← Task → ValueTask
        GetScholarshipQuery request, CancellationToken ct)
    {
        // ... (same logic)
    }
}
```

**Required changes:**
1. Change namespace `MediatR` → `Mediator`
2. Change `Task<T>` → `ValueTask<T>` in handlers
3. Update DI registration

---

## 8. Selection Guide

### 8.1 Decision matrix

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PROFILE SELECTION GUIDE                          │
├─────────────────────┬───────────┬───────────┬───────────────────────┤
│     Criteria        │  BASIC    │ STANDARD  │      ADVANCED         │
├─────────────────────┼───────────┼───────────┼───────────────────────┤
│ CRUD operations     │   >80%    │  50-80%   │       <50%            │
│ Business logic      │   Little  │  Moderate │      Complex          │
│ Team size           │   1-2     │    2-5    │        5+             │
│ Project duration    │  <6 months│ 6-18 months│     >18 months       │
│ Integrations        │   0-2     │    2-5    │        5+             │
│ Expected scale      │   Low     │   Medium  │       High            │
│ Testing required    │  Basic    │   Medium  │     Exhaustive        │
│ Team experience     │  Junior   │   Mixed   │      Senior           │
├─────────────────────┼───────────┼───────────┼───────────────────────┤
│ Files/entity        │    4-6    │   8-12    │       15-20           │
│ Initial setup       │  1 hour   │  2-3 hours│     4-8 hours         │
│ Learning curve      │  1 day    │  3-5 days │    1-2 weeks          │
└─────────────────────┴───────────┴───────────┴───────────────────────┘
```

### 8.2 Decision tree

```
                        Is it mainly CRUD?
                                  │
                    ┌─────────────┼─────────────┐
                    │             │             │
                   Yes         Partial         No
                  (>80%)       (50-80%)       (<50%)
                    │             │             │
                    │             │             │
              Is team small       │      Is domain very complex?
              or junior?          │             │
                    │             │       ┌─────┴─────┐
              ┌─────┴─────┐       │       │           │
              │           │       │      Yes          No
             Yes          No      │       │           │
              │           │       │       │           │
              ▼           │       │       ▼           │
         ┌────────┐       │       │  ┌──────────┐    │
         │ BASIC  │       │       │  │ ADVANCED │    │
         └────────┘       │       │  └──────────┘    │
                         │       │                   │
                         └───────┴───────────────────┘
                                       │
                                       ▼
                               ┌──────────┐
                               │ STANDARD │
                               └──────────┘
```

### 8.3 Project examples by profile

| Project | Profile | Justification |
|---------|---------|---------------|
| Document manager | BASIC | Pure CRUD, no logic |
| Employee internal portal | BASIC | CRUD + simple queries |
| Grant management API | STANDARD | Validations, workflows |
| Enrollment system | STANDARD | Integrations, moderate rules |
| Complete academic ERP | ADVANCED | Complex domain, scale |
| Payment system | ADVANCED | Audit, high availability |

---

## 9. Implementation by Profile

### 9.1 NuGets by profile

**BASIC:**
```xml
<ItemGroup>
  <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="10.*" />
  <PackageReference Include="FluentValidation" Version="11.*" />
  <PackageReference Include="Serilog.AspNetCore" Version="9.*" />
</ItemGroup>
```

**STANDARD:**
```xml
<ItemGroup>
  <!-- Mediator (free alternative to MediatR) -->
  <PackageReference Include="Mediator.Abstractions" Version="2.*" />
  <PackageReference Include="Mediator.SourceGenerator" Version="2.*" />

  <!-- Validation -->
  <PackageReference Include="FluentValidation" Version="11.*" />
  <PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="11.*" />

  <!-- Mapping -->
  <PackageReference Include="Mapster" Version="7.*" />

  <!-- EF Core -->
  <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="10.*" />

  <!-- Logging -->
  <PackageReference Include="Serilog.AspNetCore" Version="9.*" />
</ItemGroup>
```

**ADVANCED:**
```xml
<ItemGroup>
  <!-- Everything from STANDARD + -->

  <!-- Domain Events -->
  <PackageReference Include="MassTransit" Version="8.*" />

  <!-- Outbox Pattern (optional) -->
  <PackageReference Include="MassTransit.EntityFrameworkCore" Version="8.*" />

  <!-- Optimized read (optional) -->
  <PackageReference Include="Dapper" Version="2.*" />
</ItemGroup>
```

### 9.2 DI registration

**BASIC:**
```csharp
// Program.cs
builder.Services.AddScoped<IScholarshipService, ScholarshipService>();
builder.Services.AddScoped<IScholarshipRepository, ScholarshipRepository>();
builder.Services.AddDbContext<ApplicationDbContext>(...);
```

**STANDARD:**
```csharp
// Program.cs
builder.Services.AddMediator(options =>
{
    options.ServiceLifetime = ServiceLifetime.Scoped;
});

builder.Services.AddSingleton(typeof(IPipelineBehavior<,>), typeof(ValidationBehaviour<,>));
builder.Services.AddSingleton(typeof(IPipelineBehavior<,>), typeof(LoggingBehaviour<,>));

builder.Services.AddValidatorsFromAssemblyContaining<Program>();

builder.Services.AddScoped<IScholarshipRepository, ScholarshipRepository>();
builder.Services.AddScoped<IUnitOfWork, UnitOfWork>();
```

**ADVANCED:**
```csharp
// Everything from STANDARD +
builder.Services.AddScoped<IScholarshipWriteRepository, ScholarshipWriteRepository>();
builder.Services.AddScoped<IScholarshipReadRepository, ScholarshipReadRepository>();

// MassTransit for events
builder.Services.AddMassTransit(x =>
{
    x.AddConsumersFromNamespaceContaining<ScholarshipCreatedEventHandler>();
    x.UsingInMemory((context, cfg) =>
    {
        cfg.ConfigureEndpoints(context);
    });
});
```

---

## 10. Migration Between Profiles

### 10.1 BASIC → STANDARD

1. Create Application, Domain, Infrastructure layers
2. Move entities to Domain
3. Create Requests/Handlers for each operation
4. Replace direct calls with `_mediator.Send()`
5. Add pipeline behaviors
6. Update tests

### 10.2 STANDARD → ADVANCED

1. Separate Commands and Queries into folders
2. Create optimized read models
3. Create separate Read/Write repositories
4. Implement Domain Events
5. (Optional) Separate databases
6. Implement synchronization

### 10.3 Advice

> **Start simple, evolve when necessary.**
> It's easier to add complexity than to remove it.

---

## 11. References

### 11.1 Official documentation

| Resource | URL |
|---------|-----|
| Mediator (Othamar) | github.com/martinothamar/Mediator |
| Clean Architecture | blog.cleancoder.com/uncle-bob |
| CQRS - Martin Fowler | martinfowler.com/bliki/CQRS.html |
| DDD Reference | domainlanguage.com/ddd/reference |

### 11.2 Recommended books

- "Clean Architecture" - Robert C. Martin
- "Implementing Domain-Driven Design" - Vaughn Vernon
- "Patterns of Enterprise Application Architecture" - Martin Fowler

### 11.3 Related files in template

| File | Content |
|------|---------|
| `.claude/rules/application.md` | Application layer rules |
| `.claude/rules/domain.md` | Domain layer rules |
| `.claude/rules/infrastructure.md` | Infrastructure layer rules |
| `.claude/CLAUDE_BASE.md` | General standards |

---

*Document generated: 2026-02-02*
*Version: 1.0.0*
*la organización*
