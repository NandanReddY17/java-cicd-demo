package com.example.cicddemo;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Web-layer tests: sends HTTP requests to the controller through MockMvc. */
@WebMvcTest(CalculatorController.class)
@Import(CalculatorService.class)
class CalculatorControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void addsTwoNumbers() throws Exception {
        mockMvc.perform(get("/api/calculate").param("a", "8").param("b", "2").param("op", "add"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.result").value(10.0))
            .andExpect(jsonPath("$.op").value("add"));
    }

    @Test
    void dividesTwoNumbers() throws Exception {
        mockMvc.perform(get("/api/calculate").param("a", "9").param("b", "2").param("op", "divide"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.result").value(4.5));
    }

    @Test
    void divideByZeroReturns400() throws Exception {
        mockMvc.perform(get("/api/calculate").param("a", "1").param("b", "0").param("op", "divide"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.error").value("Cannot divide by zero"));
    }

    @Test
    void nonNumericInputReturns400() throws Exception {
        mockMvc.perform(get("/api/calculate").param("a", "abc").param("b", "2").param("op", "add"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.error").exists());
    }

    @Test
    void missingParameterReturns400() throws Exception {
        mockMvc.perform(get("/api/calculate").param("a", "1").param("op", "add"))
            .andExpect(status().isBadRequest());
    }
}
