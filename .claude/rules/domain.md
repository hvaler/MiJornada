---
globs:
  - "**/Domain/**/*.cs"
  - "**/Entities/**/*.cs"
  - "**/ValueObjects/**/*.cs"
  - "**/Aggregates/**/*.cs"
  - "**/Events/**/*.cs"
  - "**/*Entity.cs"
  - "**/*Aggregate.cs"
---

# Reglas para Capa de Dominio

> Este archivo aplica cuando Claude trabaja con entidades, value objects y lógica de dominio.
> El dominio debe ser **agnóstico a la infraestructura**.

---

## PRINCIPIOS FUNDAMENTALES

| Principio | Descripción |
|-----------|-------------|
| **Agnóstico** | Sin dependencias de EF, HTTP, bases de datos |
| **Rico** | Lógica de negocio en entidades, no en servicios |
| **Inmutable** | Value Objects inmutables |
| **Validado** | Entidades siempre en estado válido |

---

## PARTE 1: ENTIDAD BASE

### Entity Base - .NET 10 (C# 13)

```csharp
public abstract class Entity : IEquatable<Entity>
{
    public int Id { get; protected set; }

    // Eventos de dominio
    private readonly List<IDomainEvent> _domainEvents = [];
    public IReadOnlyCollection<IDomainEvent> DomainEvents => _domainEvents.AsReadOnly();

    protected void AddDomainEvent(IDomainEvent domainEvent)
    {
        _domainEvents.Add(domainEvent);
    }

    public void ClearDomainEvents()
    {
        _domainEvents.Clear();
    }

    // Igualdad por ID
    public override bool Equals(object? obj)
    {
        return obj is Entity entity && Equals(entity);
    }

    public bool Equals(Entity? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        if (GetType() != other.GetType()) return false;
        if (Id == default || other.Id == default) return false;
        return Id == other.Id;
    }

    public override int GetHashCode()
    {
        return Id.GetHashCode();
    }

    public static bool operator ==(Entity? left, Entity? right)
    {
        return Equals(left, right);
    }

    public static bool operator !=(Entity? left, Entity? right)
    {
        return !Equals(left, right);
    }
}

// Entidad auditable
public abstract class AuditableEntity : Entity, IAuditable
{
    public DateTime CreatedAt { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? ModifiedAt { get; set; }
    public string? ModifiedBy { get; set; }
}

// Soft delete
public interface ISoftDelete
{
    bool IsDeleted { get; }
    DateTime? DeletedAt { get; }
    string? DeletedBy { get; }
}
```

---

## PARTE 2: ENTIDAD DE DOMINIO

### Ejemplo: Scholarship

```csharp
public class Scholarship : AuditableEntity, ISoftDelete
{
    // ═══════════════════════════════════════════════════════════════
    // PROPIEDADES - Solo getters públicos, setters privados
    // ═══════════════════════════════════════════════════════════════
    
    public string Code { get; private set; } = null!;
    public string Name { get; private set; } = null!;
    public string? Description { get; private set; }
    public decimal Amount { get; private set; }
    public Period Period { get; private set; } = null!;  // Value Object
    public ScholarshipStatus Status { get; private set; }
    
    // Soft delete
    public bool IsDeleted { get; private set; }
    public DateTime? DeletedAt { get; private set; }
    public string? DeletedBy { get; private set; }

    // Navegación (solo lectura)
    private readonly List<ScholarshipApplication> _applications = [];
    public IReadOnlyCollection<ScholarshipApplication> Applications => _applications.AsReadOnly();

    // ═══════════════════════════════════════════════════════════════
    // CONSTRUCTOR - Privado para forzar uso de factory
    // ═══════════════════════════════════════════════════════════════
    
    private Scholarship() { } // Para EF

    private Scholarship(string code, string name, decimal amount, Period period)
    {
        Code = code;
        Name = name;
        Amount = amount;
        Period = period;
        Status = ScholarshipStatus.Draft;
    }

    // ═══════════════════════════════════════════════════════════════
    // FACTORY - Punto único de creación con validación
    // ═══════════════════════════════════════════════════════════════
    
    public static Scholarship Create(string code, string name, decimal amount, Period period)
    {
        // Validaciones de dominio
        if (string.IsNullOrWhiteSpace(code))
            throw new DomainException("Code is required");
        
        if (string.IsNullOrWhiteSpace(name))
            throw new DomainException("Name is required");
        
        if (name.Length > 200)
            throw new DomainException("Name cannot exceed 200 characters");
        
        if (amount <= 0)
            throw new DomainException("Amount must be positive");
        
        if (amount > 100_000)
            throw new DomainException("Maximum amount is 100,000");

        var scholarship = new Scholarship(code.ToUpperInvariant(), name.Trim(), amount, period);
        
        // Evento de dominio
        scholarship.AddDomainEvent(new ScholarshipCreatedEvent(scholarship.Id, scholarship.Code, scholarship.Name));
        
        return scholarship;
    }

    // ═══════════════════════════════════════════════════════════════
    // COMPORTAMIENTOS - Métodos con lógica de negocio
    // ═══════════════════════════════════════════════════════════════
    
    public void Publish()
    {
        if (Status != ScholarshipStatus.Draft)
            throw new DomainException("Only draft scholarships can be published");
        
        if (!Period.IsFuture())
            throw new DomainException("Cannot publish a scholarship with a past period");

        Status = ScholarshipStatus.Published;
        AddDomainEvent(new ScholarshipPublishedEvent(Id, Code));
    }

    public void Close()
    {
        if (Status != ScholarshipStatus.Published)
            throw new DomainException("Only published scholarships can be closed");

        Status = ScholarshipStatus.Closed;
        AddDomainEvent(new ScholarshipClosedEvent(Id));
    }

    public void UpdateAmount(decimal newAmount)
    {
        if (Status != ScholarshipStatus.Draft)
            throw new DomainException("Amount can only be modified in draft state");
        
        if (newAmount <= 0)
            throw new DomainException("Amount must be positive");

        var previousAmount = Amount;
        Amount = newAmount;
        
        AddDomainEvent(new ScholarshipAmountModifiedEvent(Id, previousAmount, newAmount));
    }

    public void AddScholarshipApplication(ScholarshipApplication application)
    {
        if (Status != ScholarshipStatus.Published)
            throw new DomainException("Applications are only accepted for published scholarships");
        
        if (!Period.Contains(DateTime.Today))
            throw new DomainException("Outside the application period");
        
        if (_applications.Any(s => s.StudentId == application.StudentId))
            throw new DomainException("Student already has an application for this scholarship");

        _applications.Add(application);
    }

    public void Delete(string user)
    {
        if (Status == ScholarshipStatus.Published && _applications.Any())
            throw new DomainException("Cannot delete a scholarship with applications");

        IsDeleted = true;
        DeletedAt = DateTime.UtcNow;
        DeletedBy = user;
    }
}

// Enum de dominio
public enum ScholarshipStatus
{
    Draft = 0,
    Published = 1,
    Closed = 2,
    Cancelled = 3
}
```

---

## PARTE 3: VALUE OBJECTS

### Value Object Base

```csharp
public abstract class ValueObject : IEquatable<ValueObject>
{
    protected abstract IEnumerable<object?> GetEqualityComponents();

    public override bool Equals(object? obj)
    {
        if (obj is null || obj.GetType() != GetType())
            return false;

        return Equals((ValueObject)obj);
    }

    public bool Equals(ValueObject? other)
    {
        if (other is null) return false;
        return GetEqualityComponents().SequenceEqual(other.GetEqualityComponents());
    }

    public override int GetHashCode()
    {
        return GetEqualityComponents()
            .Select(x => x?.GetHashCode() ?? 0)
            .Aggregate((x, y) => x ^ y);
    }

    public static bool operator ==(ValueObject? left, ValueObject? right)
    {
        return Equals(left, right);
    }

    public static bool operator !=(ValueObject? left, ValueObject? right)
    {
        return !Equals(left, right);
    }
}
```

### Ejemplo: Period

```csharp
public class Period : ValueObject
{
    public DateTime StartDate { get; }
    public DateTime EndDate { get; }

    // Duración calculada
    public int TotalDays => (EndDate - StartDate).Days;

    private Period() { } // Para EF

    public Period(DateTime startDate, DateTime endDate)
    {
        if (endDate <= startDate)
            throw new DomainException("End date must be after start date");

        StartDate = startDate.Date;
        EndDate = endDate.Date;
    }

    public bool Contains(DateTime date) 
        => date.Date >= StartDate && date.Date <= EndDate;

    public bool IsFuture() 
        => StartDate > DateTime.Today;

    public bool IsActive() 
        => Contains(DateTime.Today);

    public bool Overlaps(Period other)
        => StartDate <= other.EndDate && other.StartDate <= EndDate;

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return StartDate;
        yield return EndDate;
    }

    public override string ToString() 
        => $"{StartDate:dd/MM/yyyy} - {EndDate:dd/MM/yyyy}";
}
```

### Ejemplo: Money (Money Pattern)

```csharp
public class Money : ValueObject
{
    public decimal Amount { get; }
    public string Currency { get; }

    private Money() { }

    public Money(decimal amount, string currency = "EUR")
    {
        if (amount < 0)
            throw new DomainException("Amount cannot be negative");
        
        Amount = Math.Round(amount, 2);
        Currency = currency.ToUpperInvariant();
    }

    public static Money Euros(decimal amount) => new(amount, "EUR");
    public static Money Zero => new(0, "EUR");

    public Money Add(Money other)
    {
        if (Currency != other.Currency)
            throw new DomainException("Cannot add different currencies");
        
        return new Money(Amount + other.Amount, Currency);
    }

    protected override IEnumerable<object?> GetEqualityComponents()
    {
        yield return Amount;
        yield return Currency;
    }

    public override string ToString() => $"{Amount:N2} {Currency}";
}
```

---

## PARTE 4: EVENTOS DE DOMINIO

```csharp
public interface IDomainEvent
{
    DateTime OccurredOn { get; }
}

public abstract record DomainEvent : IDomainEvent
{
    public DateTime OccurredOn { get; } = DateTime.UtcNow;
}

// Eventos específicos
public record ScholarshipCreatedEvent(int ScholarshipId, string Code, string Name) : DomainEvent;
public record ScholarshipPublishedEvent(int ScholarshipId, string Code) : DomainEvent;
public record ScholarshipClosedEvent(int ScholarshipId) : DomainEvent;
public record ScholarshipAmountModifiedEvent(int ScholarshipId, decimal PreviousAmount, decimal NewAmount) : DomainEvent;
```

---

## PARTE 5: EXCEPCIONES DE DOMINIO

```csharp
public class DomainException : Exception
{
    public DomainException(string message) : base(message) { }
    public DomainException(string message, Exception innerException) : base(message, innerException) { }
}

public class NotFoundException : DomainException
{
    public NotFoundException(string entityName, object id) 
        : base($"{entityName} with ID {id} not found") { }
}

public class BusinessRuleException : DomainException
{
    public string RuleCode { get; }
    
    public BusinessRuleException(string ruleCode, string message) : base(message)
    {
        RuleCode = ruleCode;
    }
}
```

---

## PARTE 6: INTERFACES DE REPOSITORIO

```csharp
// En Domain - Solo contratos
public interface IScholarshipRepository
{
    Task<Scholarship?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<Scholarship?> GetByCodeAsync(string code, CancellationToken ct = default);
    Task<IReadOnlyList<Scholarship>> GetActiveAsync(CancellationToken ct = default);
    Task<Scholarship> AddAsync(Scholarship scholarship, CancellationToken ct = default);
    Task UpdateAsync(Scholarship scholarship, CancellationToken ct = default);
    Task<bool> ExistsCodeAsync(string code, CancellationToken ct = default);
}

// Patrón Specification (opcional)
public interface ISpecification<T>
{
    Expression<Func<T, bool>> ToExpression();
}

public class ActiveScholarshipsSpec : ISpecification<Scholarship>
{
    public Expression<Func<Scholarship, bool>> ToExpression()
        => b => b.Status == ScholarshipStatus.Published && !b.IsDeleted;
}
```

---

## CHECKLIST

### Entidades
- [ ] Constructor privado + factory Create()
- [ ] Propiedades con setter privado
- [ ] Validaciones en factory/métodos
- [ ] Eventos de dominio para cambios importantes
- [ ] Sin dependencias de infraestructura

### Value Objects
- [ ] Inmutables (sin setters)
- [ ] Validación en constructor
- [ ] Igualdad por valor
- [ ] Operaciones que retornan nuevo VO

### General
- [ ] Excepciones de dominio específicas
- [ ] Interfaces de repositorio (solo contratos)
- [ ] Sin referencias a EF, HTTP, JSON

---

*Regla condicional v3.7.0 - Domain-Driven Design*
