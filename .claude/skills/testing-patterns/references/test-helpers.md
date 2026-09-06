# Helpers y Builders para Tests

> Patrones de Test Data Builder para crear datos de test de forma fluida.
> Incluye: builder pattern, uso con Bogus para datos aleatorios.

---

## Test Data Builder

```csharp
public class ScholarshipBuilder
{
    private string _nombre = "Scholarship Test";
    private decimal _importe = 5000m;
    private ScholarshipStatus _estado = ScholarshipStatus.Draft;

    public ScholarshipBuilder ConNombre(string name)
    {
        _nombre = name;
        return this;
    }

    public ScholarshipBuilder ConAmount(decimal amount)
    {
        _importe = amount;
        return this;
    }

    public ScholarshipBuilder Published()
    {
        _estado = ScholarshipStatus.Published;
        return this;
    }

    public Scholarship Build()
    {
        var period = new Period(
            DateTime.Today.AddDays(1),
            DateTime.Today.AddMonths(6));
        var scholarship = Scholarship.Create("BECA-" + Guid.NewGuid().ToString()[..8], _nombre, _importe, period);

        if (_estado == ScholarshipStatus.Published)
            scholarship.Publish();

        return scholarship;
    }
}

// Uso
var scholarship = new ScholarshipBuilder()
    .ConNombre("Scholarship Excelencia")
    .ConAmount(10000m)
    .Published()
    .Build();
```

---

> Para builders mas avanzados con Bogus, ver `patterns/builders.md`.
> Para factories centralizadas, ver `patterns/test-data-factory.md`.
