# Patrón Test Data Factory

> Skill: testing-patterns
> Versión: 2.8.0

---

## Descripción

El patrón Test Data Factory centraliza la creación de datos de prueba en una clase estática,
proporcionando métodos para generar entidades, DTOs y requests con valores por defecto válidos.
Complementa al patrón Builder ofreciendo accesos directos para escenarios comunes.

---

## Factory Base

```csharp
public static class TestDataFactory
{
    // ═══════════════════════════════════════════════════════════════
    // BUILDERS - Acceso fluido a builders específicos
    // ═══════════════════════════════════════════════════════════════

    public static ScholarshipBuilder Scholarship() => new();
    public static ScholarshipApplicationBuilder ScholarshipApplication() => new();
    public static StudentBuilder Student() => new();
    public static CreateScholarshipRequestBuilder CreateScholarshipRequest() => new();

    // ═══════════════════════════════════════════════════════════════
    // ESCENARIOS PREDEFINIDOS - Entidades listas para usar
    // ═══════════════════════════════════════════════════════════════

    public static Scholarship ScholarshipDraftValida() => new ScholarshipBuilder()
        .ConCode("BECA-TEST-001")
        .ConNombre("Scholarship de Prueba")
        .ConAmount(5000m)
        .ConPeriod(DateTime.Today.AddDays(1), DateTime.Today.AddMonths(6))
        .Build();

    public static Scholarship ScholarshipPublishedValida() => new ScholarshipBuilder()
        .ConCode("BECA-PUB-001")
        .Published()
        .ConPeriod(DateTime.Today, DateTime.Today.AddMonths(6))
        .Build();

    public static Scholarship ScholarshipClosedConApplications(int numApplications = 10) => new ScholarshipBuilder()
        .ConCode("BECA-CERR-001")
        .Closed()
        .ConApplications(numApplications)
        .Build();

    public static Student StudentActive() => new StudentBuilder()
        .ConNombre("Student Test")
        .ConEmail("test@example.com")
        .Active()
        .Build();
}
```

---

## Escenarios de Listas

```csharp
public static class TestDataFactory
{
    // Listas para tests de paginación y filtrado

    public static List<Scholarship> ListaScholarshipsMixtas(int amount = 20)
    {
        var scholarships = new List<Scholarship>();
        var estados = new[] { ScholarshipStatus.Draft, ScholarshipStatus.Published, ScholarshipStatus.Closed };

        for (int i = 0; i < amount; i++)
        {
            scholarships.Add(new ScholarshipBuilder()
                .ConId(i + 1)
                .ConCode($"BECA-{i + 1:D3}")
                .ConNombre($"Scholarship Test {i + 1}")
                .ConAmount(1000m + (i * 500m))
                .ConEstado(estados[i % estados.Length])
                .Build());
        }

        return scholarships;
    }

    public static List<ScholarshipDto> ListaScholarshipDtos(int amount = 10)
    {
        return Enumerable.Range(1, amount)
            .Select(i => new ScholarshipDtoBuilder()
                .ConId(i)
                .ConNombre($"Scholarship DTO {i}")
                .ConAmount(i * 1000m)
                .Build())
            .ToList();
    }
}
```

---

## Datos Inválidos para Tests Negativos

```csharp
public static class TestDataFactory
{
    // Requests inválidos para validar errores

    public static CreateScholarshipCommand RequestSinNombre() => new CreateScholarshipRequestBuilder()
        .SinNombre()
        .Build();

    public static CreateScholarshipCommand RequestConAmountNegativo() => new CreateScholarshipRequestBuilder()
        .ConAmountInvalido()
        .Build();

    public static CreateScholarshipCommand RequestConFechasInvalidas() => new CreateScholarshipRequestBuilder()
        .ConFechasInvalidas()
        .Build();

    // Colección de casos inválidos para Theory
    public static IEnumerable<object[]> RequestsInvalidos()
    {
        yield return new object[] { RequestSinNombre(), "name" };
        yield return new object[] { RequestConAmountNegativo(), "amount" };
        yield return new object[] { RequestConFechasInvalidas(), "fecha" };
    }
}
```

---

## Uso en Tests

```csharp
public class ScholarshipServiceTests
{
    [Fact]
    public async Task GetById_ScholarshipExists_ReturnsScholarshipDto()
    {
        // Arrange - Escenario predefinido
        var scholarship = TestDataFactory.ScholarshipPublishedValida();

        _repositoryMock
            .Setup(r => r.GetByIdAsync(scholarship.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(scholarship);

        // Act
        var result = await _sut.GetByIdAsync(scholarship.Id);

        // Assert
        result.Should().NotBeNull();
    }

    [Fact]
    public async Task GetAll_ReturnsPaginado()
    {
        // Arrange - Lista predefinida
        var scholarships = TestDataFactory.ListaScholarshipsMixtas(50);

        _repositoryMock
            .Setup(r => r.GetAllAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(scholarships);

        // Act
        var result = await _sut.GetPaginatedAsync(1, 10);

        // Assert
        result.Items.Should().HaveCount(10);
        result.TotalCount.Should().Be(50);
    }

    [Theory]
    [MemberData(nameof(TestDataFactory.RequestsInvalidos), MemberType = typeof(TestDataFactory))]
    public async Task Create_InvalidData_ThrowsValidationException(
        CreateScholarshipCommand request, string campoEsperado)
    {
        // Act
        var act = () => _sut.CreateAsync(request);

        // Assert
        await act.Should().ThrowAsync<ValidationException>()
            .Where(e => e.Errors.ContainsKey(campoEsperado));
    }
}
```

---

## Factory vs Builder

| Aspecto | TestDataFactory | Builder |
|---------|-----------------|---------|
| **Uso** | Escenarios comunes predefinidos | Configuración granular |
| **Sintaxis** | `TestDataFactory.ScholarshipPublicadaValida()` | `new ScholarshipBuilder().Publicada().Build()` |
| **Personalización** | Baja (escenarios fijos) | Alta (método por propiedad) |
| **Mejor para** | Tests simples, datos por defecto | Tests que requieren variaciones |

Se recomienda usar ambos: Factory para escenarios comunes y Builder cuando se necesita
personalizar propiedades específicas del objeto de test.

---

*Pattern v1.0 - testing-patterns skill*
