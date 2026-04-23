package com.example.untitled1

import com.hiro.hiroapp.R
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
                        text = stringResource(R.string.welcome_back),
                        color = Color.White.copy(alpha = 0.8f),
                        fontSize = 16.sp
                    )
                    Text(
                        text = stringResource(R.string.find_local_pros),
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
                        text = stringResource(R.string.search_hint),
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
                text = stringResource(R.string.categories),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
            TextButton(onClick = { /* TODO */ }) {
                Text(
                    text = stringResource(R.string.see_all) + " →",
                    color = Color(0xFF1976D2),
                    fontSize = 14.sp
                )
            }
        }
        Spacer(modifier = Modifier.height(16.dp))
        val categories = listOf(
            CategoryItem(stringResource(R.string.plumber), Color(0xFFE3F2FD), Color(0xFF1E88E5)),
            CategoryItem(stringResource(R.string.carpenter), Color(0xFFFFF8E1), Color(0xFFFFA000)),
            CategoryItem(stringResource(R.string.electrician), Color(0xFFFFFDE7), Color(0xFFFBC02D)),
            CategoryItem(stringResource(R.string.painter), Color(0xFFFCE4EC), Color(0xFFD81B60)),
            CategoryItem(stringResource(R.string.cleaner), Color(0xFFE8F5E9), Color(0xFF43A047)),
            CategoryItem(stringResource(R.string.handyman), Color(0xFFF3E5F5), Color(0xFF8E24AA)),
            CategoryItem(stringResource(R.string.landscaper), Color(0xFFE8F5E9), Color(0xFF2E7D32)),
            CategoryItem(stringResource(R.string.hvac), Color(0xFFE0F7FA), Color(0xFF00ACC1))
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
                text = stringResource(R.string.top_rated),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
            TextButton(onClick = { /* TODO */ }) {
                Text(
                    text = stringResource(R.string.view_all) + " →",
                    color = Color(0xFF1976D2),
                    fontSize = 14.sp
                )
            }
        }
        // Placeholder for list of top rated pros
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
            label = { Text(stringResource(R.string.home)) },
            selected = true,
            onClick = { /* TODO */ }
        )
        NavigationBarItem(
            icon = { IconPlaceholder(modifier = Modifier.size(24.dp), color = Color.Gray) },
            label = { Text(stringResource(R.string.search)) },
            selected = false,
            onClick = { /* TODO */ }
        )
        NavigationBarItem(
            icon = { IconPlaceholder(modifier = Modifier.size(24.dp), color = Color.Gray) },
            label = { Text(stringResource(R.string.messages)) },
            selected = false,
            onClick = { /* TODO */ }
        )
        NavigationBarItem(
            icon = { IconPlaceholder(modifier = Modifier.size(24.dp), color = Color.Gray) },
            label = { Text(stringResource(R.string.profile)) },
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
