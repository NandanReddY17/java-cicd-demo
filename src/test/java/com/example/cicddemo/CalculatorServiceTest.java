package com.example.cicddemo;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

/** Plain unit tests: no Spring, no web server, just the maths. */
class CalculatorServiceTest {

    private final CalculatorService calculator = new CalculatorService();

    @ParameterizedTest(name = "{0} {2} {1} = {3}")
    @CsvSource({
        "2,    3,   add,       5",
        "10,   4,   subtract,  6",
        "-3,   7,   add,       4",
        "6,    7,   multiply,  42",
        "20,   4,   divide,    5",
        "7,    2,   divide,    3.5",
        "10,   3,   modulo,    1",
        "2,    10,  power,     1024",
        "5,    3,   ADD,       8"
    })
    void calculatesCorrectly(double a, double b, String op, double expected) {
        assertEquals(expected, calculator.calculate(a, b, op), 1e-9);
    }

    @Test
    void divideByZeroIsRejected() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
            () -> calculator.calculate(5, 0, "divide"));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }

    @Test
    void moduloByZeroIsRejected() {
        assertThrows(IllegalArgumentException.class, () -> calculator.calculate(5, 0, "modulo"));
    }

    @Test
    void unknownOperationIsRejected() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
            () -> calculator.calculate(1, 2, "sqrt"));
        assertEquals("Unknown operation: sqrt", ex.getMessage());
    }
}
