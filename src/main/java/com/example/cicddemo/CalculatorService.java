package com.example.cicddemo;

import org.springframework.stereotype.Service;

/** Business logic for the calculator. Kept separate from the web layer so it can be unit tested directly. */
@Service
public class CalculatorService {

    public double calculate(double a, double b, String operation) {
        if (operation == null) {
            throw new IllegalArgumentException("Operation is required");
        }
        switch (operation.toLowerCase()) {
            case "add":
                return a + b;
            case "subtract":
                return a - b;
            case "multiply":
                return a * b;
            case "divide":
                if (b == 0) {
                    throw new IllegalArgumentException("Cannot divide by zero");
                }
                return a / b;
            case "modulo":
                if (b == 0) {
                    throw new IllegalArgumentException("Cannot divide by zero");
                }
                return a % b;
            case "power":
                return Math.pow(a, b);
            default:
                throw new IllegalArgumentException("Unknown operation: " + operation);
        }
    }
}
