package com.hirehub.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun HomeScreen(modifier: Modifier = Modifier) {
    Scaffold(
        bottomBar = { BottomNavigationBar() },
        containerColor = Color.White
    ) { paddingValues ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            HeaderSection()
            CategoriesSection()
            TopRatedSection()
        }
    }
}

@Composable
fun HeaderSection() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(200.dp)
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(Color(0xFF1E88E5), Color(0xFF1976D2))
                ),
                shape = RoundedCornerShape(bottomStart = 32.dp, bottomEnd = 32.dp)
            )
            .padding(horizontal = 24.dp, vertical = 24.dp)
    ) {
        Column {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Welcome back",
                        color = Color.White.copy(alpha = 0.8f),
                        fontSize = 16.sp
                    )
                    Text(
                        text = "Find local pros",
                        color = Color.White,
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .background(Color.White.copy(alpha = 0.2f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    IconPlaceholder(modifier = Modifier.size(24.dp), color = Color.White)
                }
            }
            Spacer(modifier = Modifier.height(24.dp))
            OutlinedTextField(
                value = "",
                onValueChange = {},
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .background(Color.White.copy(alpha = 0.1f), RoundedCornerShape(12.dp)),
                placeholder = {
                    Text(
                        text = "Search...",
                        color = Color.White.copy(alpha = 0.7f)
                    )
                },
                leadingIcon = {
                    IconPlaceholder(modifier = Modifier.size(20.dp), color = Color.White.copy(alpha = 0.7f))
                },
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedBorderColor = Color.White.copy(alpha = 0.3f),
                    focusedBorderColor = Color.White
                )
            )
        }
    }
}

@Composable
fun CategoriesSection() {
    Column(
        modifier = Modifier
            .padding(24.dp)
            .fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Categories",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
            TextButton(onClick = { /* TODO */ }) {
                Text(
                    text = "See all →",
                    color = Color(0xFF1976D2),
                    fontSize = 14.sp
                )
            }
        }
        Spacer(modifier = Modifier.height(16.dp))
        val categories = listOf(
            CategoryItem("Plumber", Color(0xFFE3F2FD), Color(0xFF1E88E5)),
            CategoryItem("Carpenter", Color(0xFFFFF8E1), Color(0xFFFFA000)),
            CategoryItem("Electrician", Color(0xFFFFFDE7), Color(0xFFFBC02D)),
            CategoryItem("Painter", Color(0xFFFCE4EC), Color(0xFFD81B60)),
            CategoryItem("Cleaner", Color(0xFFE8F5E9), Color(0xFF43A047)),
            CategoryItem("Handyman", Color(0xFFF3E5F5), Color(0xFF8E24AA)),
            CategoryItem("Landscaper", Color(0xFFE8F5E9), Color(0xFF2E7D32)),
            CategoryItem("HVAC", Color(0xFFE0F7FA), Color(0xFF00ACC1))
        )
        LazyVerticalGrid(
            columns = GridCells.Fixed(4),
            modifier = Modifier.height(180.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            items(categories) { category ->
                CategoryCard(category)
            }
        }
    }
}

@Composable
fun CategoryCard(category: CategoryItem) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .size(56.dp)
                .background(category.bgColor, RoundedCornerShape(12.dp)),
            contentAlignment = Alignment.Center
        ) {
            IconPlaceholder(modifier = Modifier.size(24.dp), color = category.iconColor)
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = category.name,
            fontSize = 12.sp,
            color = Color.DarkGray
        )
    }
}

@Composable
fun TopRatedSection() {
    Column(
        modifier = Modifier
            .padding(horizontal = 24.dp)
            .fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Top Rated",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
            TextButton(onClick = { /* TODO */ }) {
                Text(
                    text = "View all →",
                    color = Color(0xFF1976D2),
                    fontSize = 14.sp
                )
            }
        }
    }
}

@Composable
fun BottomNavigationBar() {
    NavigationBar(
        containerColor = Color.White,
        tonalElevation = 8.dp
    ) {
        NavigationBarItem(
            icon = { IconPlaceholder(modifier = Modifier.size(24.dp), color = Color(0xFF1976D2)) },
            label = { Text("Home") },
            selected = true,
            onClick = { /* TODO */ }
        )
        NavigationBarItem(
            icon = { IconPlaceholder(modifier = Modifier.size(24.dp), color = Color.Gray) },
            label = { Text("Search") },
            selected = false,
            onClick = { /* TODO */ }
        )
        NavigationBarItem(
            icon = { IconPlaceholder(modifier = Modifier.size(24.dp), color = Color.Gray) },
            label = { Text("Messages") },
            selected = false,
            onClick = { /* TODO */ }
        )
        NavigationBarItem(
            icon = { IconPlaceholder(modifier = Modifier.size(24.dp), color = Color.Gray) },
            label = { Text("Profile") },
            selected = false,
            onClick = { /* TODO */ }
        )
    }
}

@Composable
fun IconPlaceholder(modifier: Modifier = Modifier, color: Color = Color.Gray) {
    Box(
        modifier = modifier
            .background(color.copy(alpha = 0.2f), CircleShape)
            .padding(4.dp)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(color, CircleShape)
        )
    }
}

data class CategoryItem(val name: String, val bgColor: Color, val iconColor: Color)

@Preview(showBackground = true)
@Composable
fun HomeScreenPreview() {
    MaterialTheme {
        HomeScreen()
    }
}
